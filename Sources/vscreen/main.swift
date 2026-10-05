import Foundation

let vscreenVersion = "0.1.0"

/// The command list printed by `vscreen help`; docs/usage.md mirrors it.
let commandList: [(usage: String, summary: String)] = [
    ("vscreen help", "Print this command list."),
    ("vscreen doctor", "Report permissions, signature, and display state without prompting."),
    ("vscreen permissions request", "Ask macOS for Accessibility and Screen Recording for vscreen. May show system dialogs; run it yourself."),
    ("vscreen display start [--width N] [--height N] [--no-hidpi] [--origin X,Y]",
     "Create the virtual display in a background daemon. Default 1920x1200 points, HiDPI, touching the main display only at its bottom-right corner."),
    ("vscreen display status", "Show whether the daemon runs and the display is online, with its frame."),
    ("vscreen display stop", "Stop the daemon and remove the virtual display."),
]

/// Parsed `--name value` options and `--flag` switches after the command words.
struct Options {
    private var values: [String: String] = [:]
    private var flags: Set<String> = []

    init(_ arguments: [String], valueOptions: Set<String>, flagOptions: Set<String>) throws {
        var index = 0
        while index < arguments.count {
            let argument = arguments[index]
            if valueOptions.contains(argument) {
                guard index + 1 < arguments.count else { throw CLIError("bad_arguments", "\(argument) needs a value") }
                values[argument] = arguments[index + 1]
                index += 2
            } else if flagOptions.contains(argument) {
                flags.insert(argument)
                index += 1
            } else {
                throw CLIError("bad_arguments", "unknown argument: \(argument)")
            }
        }
    }

    func string(_ name: String) -> String? { values[name] }

    func int(_ name: String, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let raw = values[name] else { return fallback }
        guard let value = Int(raw), range.contains(value) else {
            throw CLIError("bad_arguments", "\(name) must be an integer in \(range.lowerBound)...\(range.upperBound)")
        }
        return value
    }

    func has(_ flag: String) -> Bool { flags.contains(flag) }
}

func route(_ arguments: [String]) throws -> JSONObject {
    let words = arguments.prefix(2).map { $0 }
    switch words.first {
    case nil, "help", "--help", "-h":
        return ["version": vscreenVersion, "commands": commandList.map { ["usage": $0.usage, "summary": $0.summary] }]
    case "doctor":
        _ = try Options(Array(arguments.dropFirst()), valueOptions: [], flagOptions: [])
        return doctor()
    case "permissions" where words.count > 1 && words[1] == "request":
        _ = try Options(Array(arguments.dropFirst(2)), valueOptions: [], flagOptions: [])
        return requestPermissions()
    case "display" where words.count > 1:
        let rest = Array(arguments.dropFirst(2))
        switch words[1] {
        case "start": return try displayStart(rest)
        case "status":
            _ = try Options(rest, valueOptions: [], flagOptions: [])
            return displayStatus()
        case "stop":
            _ = try Options(rest, valueOptions: [], flagOptions: [])
            return try displayStop()
        default: break
        }
    default: break
    }
    throw CLIError("unknown_command", "unknown command: \(arguments.joined(separator: " ")); run `vscreen help`")
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == daemonCommand {
    runDisplayDaemon(Array(arguments.dropFirst()))
}
if !["help", "--help", "-h"].contains(arguments.first ?? "help") {
    runAsOwnResponsibleProcess(arguments)
}
do {
    emitSuccess(try route(arguments))
} catch let error as CLIError {
    emitFailure(error)
} catch {
    emitFailure(CLIError("internal", "\(error)"))
}
