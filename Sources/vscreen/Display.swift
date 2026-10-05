import CPrivate
import CoreGraphics
import Darwin
import Foundation

/// Hidden argv[1] that runs the display daemon. Not listed in help.
let daemonCommand = "__display-daemon"

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser
    static let support = home.appendingPathComponent("Library/Application Support/vscreen")
    static let state = support.appendingPathComponent("display.json")
    /// Held by `display start` and `display stop` for their whole run: one at a time.
    static let controlLock = support.appendingPathComponent("display-control.lock")
    /// Held by the daemon for its whole life: at most one daemon holds a display.
    static let daemonLock = support.appendingPathComponent("display-daemon.lock")
    /// The last daemon failure (pid, code, message), read by `display start` and `status`.
    static let daemonFailure = support.appendingPathComponent("display-failure.json")
    static let logs = home.appendingPathComponent("Library/Logs/vscreen")
    static let daemonLog = logs.appendingPathComponent("daemon.log")
}

/// Worst case of the daemon's startup: lock 2 s, online 5 s, mirror recovery 5 s, placement 2 s.
/// The caller waits longer, so it never kills a daemon in the middle of a recovery.
private let daemonStartDeadline: Double = 30
private let daemonLockWait: Double = 2

private let startValueOptions: Set<String> = ["--width", "--height", "--origin"]
private let startFlagOptions: Set<String> = ["--no-hidpi"]

struct DisplayConfig {
    var width: Int
    var height: Int
    var hiDPI: Bool
    /// Global origin (top-left, points). nil = touch the main display only at its bottom-right corner.
    var origin: CGPoint?

    init(_ options: Options) throws {
        width = try options.int("--width", default: 1920, range: 640...3840)
        height = try options.int("--height", default: 1200, range: 480...2400)
        hiDPI = !options.has("--no-hidpi")
        if let raw = options.string("--origin") {
            let parts = raw.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, let x = parts[0], let y = parts[1] else {
                throw CLIError("bad_arguments", "--origin must be X,Y in global points")
            }
            // The display at (0,0) is the main display: macOS would move Adam's display away.
            guard x != 0 || y != 0 else {
                throw CLIError("bad_arguments", "--origin 0,0 would make the virtual display the main display")
            }
            origin = CGPoint(x: x, y: y)
        }
    }

    var arguments: [String] {
        var result = ["--width", "\(width)", "--height", "\(height)"]
        if !hiDPI { result.append("--no-hidpi") }
        if let origin { result += ["--origin", "\(Int(origin.x)),\(Int(origin.y))"] }
        return result
    }
}

/// Bottom-right corner of Adam's display: the virtual display touches it at one point only,
/// away from the top-left hot corner and the bottom Dock edge.
func defaultOrigin(next userDisplay: CGDirectDisplayID) -> CGPoint {
    let bounds = CGDisplayBounds(userDisplay)
    return CGPoint(x: bounds.maxX, y: bounds.maxY)
}

/// Runs one display configuration transaction for the login session.
func configureDisplays(_ body: (CGDisplayConfigRef?) -> CGError) -> CGError {
    var configRef: CGDisplayConfigRef?
    var error = CGBeginDisplayConfiguration(&configRef)
    guard error == .success else { return error }
    error = body(configRef)
    if error == .success { return CGCompleteDisplayConfiguration(configRef, .forSession) }
    CGCancelDisplayConfiguration(configRef)
    return error
}

func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count)))
}

// MARK: - Locks

/// Takes an exclusive flock on `url`, retrying until `seconds` pass. Returns the open descriptor
/// (closing it releases the lock), or nil when another process still holds the lock.
func acquireLock(_ url: URL, wait seconds: Double) throws -> Int32? {
    try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
    let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
    guard fd >= 0 else { throw CLIError("lock_failed", "open \(url.path): \(String(cString: strerror(errno)))") }
    let deadline = Date().addingTimeInterval(seconds)
    while flock(fd, LOCK_EX | LOCK_NB) != 0 {
        guard errno == EWOULDBLOCK || errno == EINTR, Date() < deadline else {
            close(fd)
            return nil
        }
        usleep(50_000)
    }
    return fd
}

/// Runs `body` while holding the control lock, so start and stop never interleave.
private func withControlLock<T>(_ body: () throws -> T) throws -> T {
    guard let fd = try acquireLock(Paths.controlLock, wait: daemonStartDeadline + 10) else {
        throw CLIError("display_busy", "another `vscreen display start|stop` still runs")
    }
    defer { close(fd) }
    return try body()
}

// MARK: - State file

func readState() -> JSONObject? {
    guard let data = try? Data(contentsOf: Paths.state) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? JSONObject
}

func writeState(_ state: JSONObject) throws {
    try FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
    try jsonData(state).write(to: Paths.state, options: .atomic)
}

/// Removes the state file only if it still belongs to `pid`.
func removeState(ownedBy pid: pid_t) {
    if let state = readState(), state["pid"] as? Int == Int(pid) {
        try? FileManager.default.removeItem(at: Paths.state)
    }
}

func readDaemonFailure(pid: pid_t) -> JSONObject? {
    guard let data = try? Data(contentsOf: Paths.daemonFailure),
          let failure = (try? JSONSerialization.jsonObject(with: data)) as? JSONObject,
          failure["pid"] as? Int == Int(pid) else { return nil }
    return failure
}

/// Records why this daemon stopped, so the caller can report the code instead of "see log".
func writeDaemonFailure(_ error: CLIError) {
    logLine("daemon failed: \(error.code): \(error.message)")
    let failure: JSONObject = ["pid": Int(getpid()), "code": error.code, "message": error.message,
                               "at": ISO8601DateFormatter().string(from: Date())]
    try? FileManager.default.createDirectory(at: Paths.support, withIntermediateDirectories: true)
    try? jsonData(failure).write(to: Paths.daemonFailure, options: .atomic)
}

// MARK: - Daemon identity

enum DaemonIdentity: String {
    /// The recorded daemon: same pid, process name, and process start time.
    case ours
    /// No process with that pid, or a different process reused it.
    case gone
    /// A live process whose name or start time cannot be read. Its state is kept.
    case unidentified
}

/// Name and start time (microseconds since 1970) of a live process.
func processIdentity(_ pid: pid_t) -> (name: String, start: Int)? {
    var info = proc_bsdinfo()
    let size = Int32(MemoryLayout<proc_bsdinfo>.size)
    guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
    let name = withUnsafeBytes(of: info.pbi_comm) { raw in
        String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
    return (name, Int(info.pbi_start_tvsec) * 1_000_000 + Int(info.pbi_start_tvusec))
}

/// Identifies the daemon by pid, process name, and the start time stored in its state.
/// The name and start time survive a reinstall that unlinks the daemon's executable.
func identifyDaemon(pid: Int, start: Int?) -> DaemonIdentity {
    guard pid > 0, let pid = pid_t(exactly: pid) else { return .gone }
    if kill(pid, 0) != 0, errno == ESRCH { return .gone }
    guard let process = processIdentity(pid) else { return .unidentified }
    guard process.name == "vscreen" else { return .gone }
    // State written before start times were stored: the name is all there is.
    guard let start else { return .ours }
    return process.start == start ? .ours : .gone
}

private func identifyDaemon(_ state: JSONObject) -> DaemonIdentity {
    identifyDaemon(pid: state["pid"] as? Int ?? 0, start: state["pidStart"] as? Int)
}

// MARK: - Commands

func displayStatus() -> JSONObject {
    guard let state = readState(), let pid = state["pid"] as? Int, let id = state["displayID"] as? Int else {
        return ["running": false, "online": false]
    }
    let identity = identifyDaemon(state)
    let running = identity == .ours
    let displayID = CGDirectDisplayID(id)
    let online = onlineDisplays().contains(displayID)
    var result: JSONObject = [
        "running": running && online,
        "daemonAlive": running,
        "online": online,
        "pid": pid,
        "displayID": id,
        "hiDPI": state["hiDPI"] as? Bool ?? false,
        "startedAt": state["startedAt"] as? String ?? "",
        "mainDisplay": rectJSON(CGDisplayBounds(CGMainDisplayID())),
    ]
    if online {
        result["frame"] = rectJSON(CGDisplayBounds(displayID))
        if let mode = CGDisplayCopyDisplayMode(displayID) {
            result["pixels"] = ["width": mode.pixelWidth, "height": mode.pixelHeight]
        }
    }
    switch identity {
    case .ours: break
    case .unidentified: result["daemonUnidentified"] = true
    case .gone:
        result["stale"] = true
        if let failure = readDaemonFailure(pid: pid_t(pid)) { result["failure"] = failure }
    }
    return result
}

private func unidentifiedError(_ pid: Int) -> CLIError {
    CLIError("daemon_unidentified",
             "process \(pid) from \(Paths.state.path) is alive but its name and start time cannot be read; the state file is kept")
}

func displayStart(_ arguments: [String]) throws -> JSONObject {
    let config = try DisplayConfig(Options(arguments, valueOptions: startValueOptions, flagOptions: startFlagOptions))
    return try withControlLock {
        let current = displayStatus()
        if current["running"] as? Bool == true {
            var result = current
            result["alreadyRunning"] = true
            return result
        }
        if let state = readState(), let pid = state["pid"] as? Int {
            switch identifyDaemon(state) {
            case .unidentified: throw unidentifiedError(pid)
            // Daemon alive but its display is gone: replace it.
            case .ours: try stopDaemon(pid: pid, start: state["pidStart"] as? Int)
            case .gone: break
            }
        }
        try? FileManager.default.removeItem(at: Paths.state)
        try FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)

        let pid = try spawnSelf([daemonCommand] + config.arguments, io: .detached(logPath: Paths.daemonLog.path))
        let deadline = Date().addingTimeInterval(daemonStartDeadline)
        while Date() < deadline {
            var status: Int32 = 0
            if waitpid(pid, &status, WNOHANG) == pid {
                throw daemonExitError(pid: pid, status: status)
            }
            if let state = readState(), state["pid"] as? Int == Int(pid) {
                var result = displayStatus()
                result["alreadyRunning"] = false
                result["placement"] = state["placement"]
                return result
            }
            usleep(50_000)
        }
        kill(pid, SIGTERM)
        throw CLIError("daemon_timeout",
                       "display daemon did not report a display within \(Int(daemonStartDeadline))s; see \(Paths.daemonLog.path)")
    }
}

/// The daemon's own failure code when it recorded one, else how it exited.
private func daemonExitError(pid: pid_t, status: Int32) -> CLIError {
    if let failure = readDaemonFailure(pid: pid), let code = failure["code"] as? String {
        return CLIError(code, "\(failure["message"] as? String ?? "") (display daemon \(pid); see \(Paths.daemonLog.path))")
    }
    let signal = status & 0x7f
    let how = signal == 0 ? "exited with code \((status >> 8) & 0xff)" : "was killed by signal \(signal)"
    return CLIError("daemon_failed", "display daemon \(pid) \(how); see \(Paths.daemonLog.path)")
}

func displayStop() throws -> JSONObject {
    try withControlLock {
        guard let state = readState(), let pid = state["pid"] as? Int else {
            return ["stopped": false, "running": false]
        }
        let displayID = CGDirectDisplayID(state["displayID"] as? Int ?? 0)
        switch identifyDaemon(state) {
        case .unidentified: throw unidentifiedError(pid)
        case .ours: try stopDaemon(pid: pid, start: state["pidStart"] as? Int)
        case .gone: break
        }
        removeState(ownedBy: pid_t(pid))
        let deadline = Date().addingTimeInterval(3)
        while onlineDisplays().contains(displayID), Date() < deadline { usleep(50_000) }
        let online = onlineDisplays().contains(displayID)
        guard !online else { throw CLIError("display_still_online", "display \(displayID) is still online after the daemon stopped") }
        return ["stopped": true, "running": false, "pid": pid, "displayID": Int(displayID), "online": false]
    }
}

private func stopDaemon(pid: Int, start: Int?) throws {
    let alive = { identifyDaemon(pid: pid, start: start) != .gone }
    kill(pid_t(pid), SIGTERM)
    let deadline = Date().addingTimeInterval(5)
    while alive(), Date() < deadline { usleep(50_000) }
    if alive() {
        kill(pid_t(pid), SIGKILL)
        usleep(200_000)
    }
    guard !alive() else { throw CLIError("daemon_stuck", "display daemon \(pid) did not exit") }
}

// MARK: - Daemon

/// Runs in the detached daemon process: creates the display, places it, writes state,
/// and holds the display until SIGTERM/SIGINT/SIGHUP.
@MainActor
final class DisplayDaemon {
    private var display: CGVirtualDisplay?
    private var signalSources: [DispatchSourceSignal] = []
    /// Held (never closed) for the daemon's life; the kernel releases it when the process exits.
    private var lockDescriptor: Int32 = -1
    /// Adam's main display, recorded before the virtual display exists.
    private var userDisplay: CGDirectDisplayID = kCGNullDirectDisplay
    private var checkScheduled = false
    private var checking = false

    static var shared: DisplayDaemon?

    func start(_ config: DisplayConfig) throws {
        // A second daemon exits here, before it can create a display with the same identity.
        guard let fd = try acquireLock(Paths.daemonLock, wait: daemonLockWait) else {
            throw CLIError("daemon_already_running", "another display daemon holds \(Paths.daemonLock.path)")
        }
        lockDescriptor = fd
        userDisplay = CGMainDisplayID()

        let scale = config.hiDPI ? 2 : 1
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = DispatchQueue.main
        descriptor.name = "vscreen"
        descriptor.maxPixelsWide = UInt32(config.width * scale)
        descriptor.maxPixelsHigh = UInt32(config.height * scale)
        // A physical size derived from pixels made a 1280x800 non-HiDPI display claim 149 mm,
        // and macOS 26.5 then mirrored Adam's display onto it. A fixed monitor-like width avoids that.
        descriptor.sizeInMillimeters = CGSize(width: 600, height: 600 * Double(config.height) / Double(config.width))
        // macOS remembers settings (mirroring, origin) per identity: vendor, product, serial.
        // Each size/HiDPI combination gets its own serial so an identity never changes mode.
        // productID 1 identities were remembered as mirrored during development; do not reuse it.
        descriptor.vendorID = 0x7673 // "vs"
        descriptor.productID = 0x0002
        descriptor.serialNum = UInt32(config.width << 13 | config.height << 1 | (config.hiDPI ? 1 : 0))
        descriptor.terminationHandler = { _, _ in
            writeDaemonFailure(CLIError("display_terminated", "the system terminated the virtual display"))
            removeState(ownedBy: getpid())
            exit(3)
        }
        guard let display = CGVirtualDisplay(descriptor: descriptor) else {
            throw CLIError("virtual_display_failed", "CGVirtualDisplay initWithDescriptor returned nil")
        }
        let settings = CGVirtualDisplaySettings()
        settings.hiDPI = config.hiDPI ? 1 : 0
        settings.modes = [CGVirtualDisplayMode(width: UInt32(config.width), height: UInt32(config.height), refreshRate: 60)]
        guard display.apply(settings) else {
            throw CLIError("virtual_display_failed", "CGVirtualDisplay applySettings returned NO")
        }
        self.display = display
        let id = display.displayID
        guard waitUntil(seconds: 5, { onlineDisplays().contains(id) }) else {
            throw CLIError("virtual_display_failed",
                           "display \(id) (serial \(descriptor.serialNum)) was created but did not come online within 5s")
        }

        // Safety net: never leave Adam's display mirrored or the virtual display as main.
        let mirroredOnArrival = takenOver(id)
        if mirroredOnArrival {
            logLine("display \(id) came online mirrored or as main; unmirroring and restoring display \(userDisplay) as main")
            try restoreUserDisplay(id)
        }

        let requested = config.origin ?? defaultOrigin(next: userDisplay)
        let error = configureDisplays { CGConfigureDisplayOrigin($0, id, Int32(requested.x), Int32(requested.y)) }
        _ = waitUntil(seconds: 2, { CGDisplayBounds(id).origin == requested })
        let frame = CGDisplayBounds(id)
        logLine("display \(id) online; requested origin \(requested), configure error \(error.rawValue), frame \(frame)")
        // Placement can move displays; exiting releases the display and gives main back.
        guard !takenOver(id) else {
            throw CLIError("display_became_main",
                           "after placement at \(requested) display \(id) is main or mirrored (main is \(CGMainDisplayID()), Adam's display \(userDisplay))")
        }

        var state: JSONObject = [
            "pid": Int(getpid()),
            "displayID": Int(id),
            "userDisplayID": Int(userDisplay),
            "hiDPI": config.hiDPI,
            "startedAt": ISO8601DateFormatter().string(from: Date()),
            "placement": [
                "requestedOrigin": ["x": Double(requested.x), "y": Double(requested.y)],
                "configureError": Int(error.rawValue),
                "accepted": frame.origin == requested,
                "mirroredOnArrival": mirroredOnArrival,
                "frame": rectJSON(frame),
            ],
        ]
        if let start = processIdentity(getpid())?.start { state["pidStart"] = start }
        try writeState(state)

        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { DisplayDaemon.shared?.shutdown(signalNumber) }
            }
            source.resume()
            signalSources.append(source)
        }

        // Watchdog: sleep/wake or a display reconnect can mirror the display or make it main later.
        CGDisplayRegisterReconfigurationCallback({ _, flags, _ in
            guard !flags.contains(.beginConfigurationFlag) else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { DisplayDaemon.shared?.scheduleCheck() }
            }
        }, nil)
    }

    /// True when the virtual display mirrors (or is mirrored) or is the main display.
    private func takenOver(_ id: CGDirectDisplayID) -> Bool {
        CGDisplayIsInMirrorSet(id) != 0 || CGMainDisplayID() == id
    }

    /// Unmirrors both displays and puts Adam's display back at (0,0), which makes it main.
    private func restoreUserDisplay(_ id: CGDirectDisplayID) throws {
        let user = userDisplay
        let error = configureDisplays { configRef in
            var error = CGConfigureDisplayMirrorOfDisplay(configRef, id, kCGNullDirectDisplay)
            if error == .success { error = CGConfigureDisplayMirrorOfDisplay(configRef, user, kCGNullDirectDisplay) }
            if error == .success { error = CGConfigureDisplayOrigin(configRef, user, 0, 0) }
            return error
        }
        guard waitUntil(seconds: 5, { CGDisplayIsInMirrorSet(id) == 0 && CGMainDisplayID() == user }) else {
            throw CLIError("display_mirrored", "display \(id) stayed mirrored or main (configure error \(error.rawValue))")
        }
    }

    /// Coalesces a burst of reconfiguration callbacks into one check after it settles.
    private func scheduleCheck() {
        guard !checkScheduled, !checking else { return }
        checkScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            MainActor.assumeIsolated {
                guard let daemon = DisplayDaemon.shared else { return }
                daemon.checkScheduled = false
                daemon.checkPlacement()
            }
        }
    }

    private func checkPlacement() {
        guard let id = display?.displayID, takenOver(id) else { return }
        checking = true
        defer { checking = false }
        logLine("watchdog: display \(id) became mirrored or main; restoring display \(userDisplay)")
        do {
            try restoreUserDisplay(id)
            logLine("watchdog: display \(userDisplay) is main again")
        } catch let error as CLIError {
            writeDaemonFailure(error)
            removeState(ownedBy: getpid())
            display = nil
            exit(4)
        } catch {
            exit(4)
        }
    }

    private func shutdown(_ signalNumber: Int32) {
        logLine("signal \(signalNumber); removing display")
        removeState(ownedBy: getpid())
        display = nil
        exit(0)
    }

    /// Polls `condition` while letting the main run loop and queue run.
    private func waitUntil(seconds: Double, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while !condition() {
            if Date() >= deadline { return false }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return true
    }
}

@MainActor
func runDisplayDaemon(_ arguments: [String]) -> Never {
    logLine("daemon \(getpid()) starting: \(arguments.joined(separator: " "))")
    do {
        let config = try DisplayConfig(Options(arguments, valueOptions: startValueOptions, flagOptions: startFlagOptions))
        let daemon = DisplayDaemon()
        DisplayDaemon.shared = daemon
        try daemon.start(config)
    } catch let error as CLIError {
        writeDaemonFailure(error)
        exit(2)
    } catch {
        writeDaemonFailure(CLIError("daemon_failed", "\(error)"))
        exit(2)
    }
    dispatchMain()
}
