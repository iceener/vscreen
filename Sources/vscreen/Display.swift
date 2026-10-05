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
    static let logs = home.appendingPathComponent("Library/Logs/vscreen")
    static let daemonLog = logs.appendingPathComponent("daemon.log")
}

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

/// Bottom-right corner of the main display: the virtual display touches it at one point only,
/// away from the top-left hot corner and the bottom Dock edge.
func defaultOrigin() -> CGPoint {
    let main = CGDisplayBounds(CGMainDisplayID())
    return CGPoint(x: main.maxX, y: main.maxY)
}

func onlineDisplays() -> [CGDirectDisplayID] {
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
    var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
    guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
    return Array(ids.prefix(Int(count)))
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

/// True when `pid` is alive and runs the vscreen executable (guards against pid reuse).
func isDaemonProcess(_ pid: pid_t) -> Bool {
    guard pid > 0, kill(pid, 0) == 0 || errno == EPERM else { return false }
    var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
    guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
    return stringFromCString(buffer).hasSuffix("/vscreen")
}

// MARK: - Commands

func displayStatus() -> JSONObject {
    guard let state = readState(), let pid = state["pid"] as? Int, let id = state["displayID"] as? Int else {
        return ["running": false, "online": false]
    }
    let running = isDaemonProcess(pid_t(pid))
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
    if !running { result["stale"] = true }
    return result
}

func displayStart(_ arguments: [String]) throws -> JSONObject {
    let config = try DisplayConfig(Options(arguments, valueOptions: startValueOptions, flagOptions: startFlagOptions))
    let current = displayStatus()
    if current["running"] as? Bool == true {
        var result = current
        result["alreadyRunning"] = true
        return result
    }
    if let pid = current["pid"] as? Int, current["daemonAlive"] as? Bool == true {
        // Daemon alive but its display is gone: replace it.
        try stopDaemon(pid_t(pid))
    }
    try? FileManager.default.removeItem(at: Paths.state)
    try FileManager.default.createDirectory(at: Paths.logs, withIntermediateDirectories: true)

    let pid = try spawnSelf([daemonCommand] + config.arguments, io: .detached(logPath: Paths.daemonLog.path))
    let deadline = Date().addingTimeInterval(10)
    while Date() < deadline {
        var status: Int32 = 0
        if waitpid(pid, &status, WNOHANG) == pid {
            throw CLIError("daemon_failed", "display daemon exited with code \((status >> 8) & 0xff); see \(Paths.daemonLog.path)")
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
    throw CLIError("daemon_timeout", "display daemon did not report a display within 10s; see \(Paths.daemonLog.path)")
}

func displayStop() throws -> JSONObject {
    guard let state = readState(), let pid = state["pid"] as? Int else {
        return ["stopped": false, "running": false]
    }
    let displayID = CGDirectDisplayID(state["displayID"] as? Int ?? 0)
    if isDaemonProcess(pid_t(pid)) { try stopDaemon(pid_t(pid)) }
    try? FileManager.default.removeItem(at: Paths.state)
    let deadline = Date().addingTimeInterval(3)
    while onlineDisplays().contains(displayID), Date() < deadline { usleep(50_000) }
    let online = onlineDisplays().contains(displayID)
    guard !online else { throw CLIError("display_still_online", "display \(displayID) is still online after the daemon stopped") }
    return ["stopped": true, "running": false, "pid": pid, "displayID": Int(displayID), "online": false]
}

private func stopDaemon(_ pid: pid_t) throws {
    kill(pid, SIGTERM)
    let deadline = Date().addingTimeInterval(5)
    while isDaemonProcess(pid), Date() < deadline { usleep(50_000) }
    if isDaemonProcess(pid) {
        kill(pid, SIGKILL)
        usleep(200_000)
    }
    guard !isDaemonProcess(pid) else { throw CLIError("daemon_stuck", "display daemon \(pid) did not exit") }
}

// MARK: - Daemon

/// Runs in the detached daemon process: creates the display, places it, writes state,
/// and holds the display until SIGTERM/SIGINT/SIGHUP.
@MainActor
final class DisplayDaemon {
    private var display: CGVirtualDisplay?
    private var signalSources: [DispatchSourceSignal] = []

    static var shared: DisplayDaemon?

    func start(_ config: DisplayConfig) throws {
        let scale = config.hiDPI ? 2 : 1
        let descriptor = CGVirtualDisplayDescriptor()
        descriptor.queue = DispatchQueue.main
        descriptor.name = "vscreen"
        descriptor.maxPixelsWide = UInt32(config.width * scale)
        descriptor.maxPixelsHigh = UInt32(config.height * scale)
        // About 218 pixels per inch, like Apple's Retina panels.
        descriptor.sizeInMillimeters = CGSize(width: Double(config.width * scale) / 218 * 25.4,
                                              height: Double(config.height * scale) / 218 * 25.4)
        descriptor.vendorID = 0x7673 // "vs"
        descriptor.productID = 0x0001
        descriptor.serialNum = 0x0001
        descriptor.terminationHandler = { _, _ in
            logLine("virtual display terminated by the system; exiting")
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
            throw CLIError("virtual_display_failed", "display \(id) did not come online within 5s")
        }

        let requested = config.origin ?? defaultOrigin()
        var configRef: CGDisplayConfigRef?
        var error = CGBeginDisplayConfiguration(&configRef)
        if error == .success { error = CGConfigureDisplayOrigin(configRef, id, Int32(requested.x), Int32(requested.y)) }
        if error == .success { error = CGCompleteDisplayConfiguration(configRef, .forSession) }
        else { CGCancelDisplayConfiguration(configRef) }
        _ = waitUntil(seconds: 2, { CGDisplayBounds(id).origin == requested })
        let frame = CGDisplayBounds(id)
        logLine("display \(id) online; requested origin \(requested), configure error \(error.rawValue), frame \(frame)")

        try writeState([
            "pid": Int(getpid()),
            "displayID": Int(id),
            "hiDPI": config.hiDPI,
            "startedAt": ISO8601DateFormatter().string(from: Date()),
            "placement": [
                "requestedOrigin": ["x": Double(requested.x), "y": Double(requested.y)],
                "configureError": Int(error.rawValue),
                "accepted": frame.origin == requested,
                "frame": rectJSON(frame),
            ],
        ])

        for signalNumber in [SIGTERM, SIGINT, SIGHUP] {
            signal(signalNumber, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
            source.setEventHandler {
                MainActor.assumeIsolated { DisplayDaemon.shared?.shutdown(signalNumber) }
            }
            source.resume()
            signalSources.append(source)
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
        logLine("daemon failed: \(error.code): \(error.message)")
        exit(2)
    } catch {
        logLine("daemon failed: \(error)")
        exit(2)
    }
    dispatchMain()
}
