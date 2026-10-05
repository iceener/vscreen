import AppKit
import ApplicationServices
import CPrivate
import CoreGraphics
import Foundation
import Security

/// Set in the re-executed child so it does not re-execute again.
private let responsibleEnv = "VSCREEN_RESPONSIBLE"

/// Real path of the running executable (symlinks resolved), e.g. inside vscreen.app.
func executablePath() -> String {
    var size: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &size)
    var buffer = [CChar](repeating: 0, count: Int(size))
    _ = _NSGetExecutablePath(&buffer, &size)
    var real = [CChar](repeating: 0, count: Int(PATH_MAX))
    if realpath(buffer, &real) != nil { return stringFromCString(real) }
    return stringFromCString(buffer)
}

enum SpawnIO {
    /// Child shares stdin/stdout/stderr with this process.
    case inherit
    /// Child starts a new session, reads /dev/null, and writes stdout/stderr to the log file.
    case detached(logPath: String)
}

/// Spawns this executable with `arguments` as its own TCC-responsible process.
/// TCC then checks vscreen's code identity, not the terminal or agent host that ran it.
func spawnSelf(_ arguments: [String], io: SpawnIO) throws -> pid_t {
    let path = executablePath()
    var attributes: posix_spawnattr_t?
    posix_spawnattr_init(&attributes)
    defer { posix_spawnattr_destroy(&attributes) }
    var actions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&actions)
    defer { posix_spawn_file_actions_destroy(&actions) }

    var flags = Int32(POSIX_SPAWN_CLOEXEC_DEFAULT)
    switch io {
    case .inherit:
        for fd: Int32 in 0...2 { posix_spawn_file_actions_addinherit_np(&actions, fd) }
    case .detached(let logPath):
        flags |= Int32(POSIX_SPAWN_SETSID)
        posix_spawn_file_actions_addopen(&actions, 0, "/dev/null", O_RDONLY, 0)
        posix_spawn_file_actions_addopen(&actions, 1, logPath, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        posix_spawn_file_actions_adddup2(&actions, 1, 2)
    }
    posix_spawnattr_setflags(&attributes, Int16(flags))
    let disclaim = responsibility_spawnattrs_setdisclaim(&attributes, 1)
    guard disclaim == 0 else {
        throw CLIError("spawn_failed", "responsibility_spawnattrs_setdisclaim failed: \(String(cString: strerror(disclaim)))")
    }

    var environment = ProcessInfo.processInfo.environment
    environment[responsibleEnv] = "1"
    let argv = ([path] + arguments).map { strdup($0) } + [nil]
    let envp = environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer {
        argv.forEach { free($0) }
        envp.forEach { free($0) }
    }
    var pid: pid_t = 0
    let status = posix_spawn(&pid, path, &actions, &attributes, argv, envp)
    guard status == 0 else {
        throw CLIError("spawn_failed", "posix_spawn \(path): \(String(cString: strerror(status)))")
    }
    return pid
}

/// Re-executes this command as its own responsible process and exits with the child's status.
/// Returns only in the child (or when already responsible).
func runAsOwnResponsibleProcess(_ arguments: [String]) {
    if ProcessInfo.processInfo.environment[responsibleEnv] == "1" { return }
    let pid: pid_t
    do {
        pid = try spawnSelf(arguments, io: .inherit)
    } catch let error as CLIError {
        emitFailure(error)
    } catch {
        emitFailure(CLIError("spawn_failed", "\(error)"))
    }
    // The wrapper outlives the child: forward SIGINT/SIGTERM so the child (e.g. `record`) stops cleanly.
    let forwarders = [SIGINT, SIGTERM].map { number in
        Darwin.signal(number, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
        source.setEventHandler { kill(pid, number) }
        source.resume()
        return source
    }
    var status: Int32 = 0
    withExtendedLifetime(forwarders) {
        while waitpid(pid, &status, 0) == -1 {
            if errno != EINTR { emitFailure(CLIError("spawn_failed", "waitpid: \(String(cString: strerror(errno)))")) }
        }
    }
    let signal = status & 0x7f
    exit(signal == 0 ? (status >> 8) & 0xff : 128 + signal)
}

/// Code signature of the running process: designated requirement and identifier.
func signatureInfo() -> JSONObject {
    var code: SecCode?
    var staticCode: SecStaticCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
          SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return ["signed": false] }
    var info: JSONObject = ["valid": SecCodeCheckValidity(code, [], nil) == errSecSuccess]

    var requirement: SecRequirement?
    var requirementText: CFString?
    if SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
       SecRequirementCopyString(requirement, [], &requirementText) == errSecSuccess, let requirementText {
        let text = requirementText as String
        info["designatedRequirement"] = text
        info["certificateBased"] = text.contains("certificate")
    }

    var signing: CFDictionary?
    if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &signing) == errSecSuccess,
       let signing = signing as? [String: Any] {
        info["identifier"] = signing[kSecCodeInfoIdentifier as String] as? String
        info["signed"] = signing[kSecCodeInfoIdentifier as String] != nil
        info["certificates"] = (signing[kSecCodeInfoCertificates as String] as? [Any])?.count ?? 0
    }
    return info
}

func frontmostAppJSON() -> JSONObject {
    guard let app = NSWorkspace.shared.frontmostApplication else { return [:] }
    return ["bundleId": app.bundleIdentifier ?? "", "name": app.localizedName ?? "", "pid": Int(app.processIdentifier)]
}

/// Non-prompting permission checks only.
func permissionState() -> JSONObject {
    ["accessibility": AXIsProcessTrusted(), "screenRecording": CGPreflightScreenCaptureAccess()]
}

func doctor() -> JSONObject {
    let executable = executablePath()
    let responsible = responsibility_get_pid_responsible_for_pid(getpid())
    var identity = signatureInfo()
    identity["pid"] = Int(getpid())
    identity["responsiblePid"] = Int(responsible)
    identity["selfResponsible"] = responsible == getpid()
    if let range = executable.range(of: ".app/Contents/MacOS/") {
        identity["bundlePath"] = String(executable[..<range.lowerBound]) + ".app"
    }
    return [
        "version": vscreenVersion,
        "executable": executable,
        "identity": identity,
        "permissions": permissionState(),
        "display": displayStatus(),
        "frontmostApp": frontmostAppJSON(),
    ]
}

/// The one command that may show system dialogs. Adam runs it himself.
func requestPermissions() -> JSONObject {
    // Value of kAXTrustedCheckOptionPrompt; the global is a mutable C var Swift 6 rejects.
    let promptKey = "AXTrustedCheckOptionPrompt"
    let accessibility = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
    let screenRecording = CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess()
    return [
        "permissions": ["accessibility": accessibility, "screenRecording": screenRecording],
        "settings": [
            "accessibility": "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "screenRecording": "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
        ],
        "note": "Allow vscreen in System Settings > Privacy & Security > Accessibility and > Screen & System Audio Recording. Screen Recording takes effect for the next vscreen run.",
    ]
}
