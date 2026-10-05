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
    ("vscreen window list [--pid P] [--app NAME] [--bundle ID] [--display virtual|main|ID] [--all-layers]",
     "List windows front to back: id (CGWindowID), pid, app, bundle id, title, frame, display, layer, on-screen, order. Layer 0 only unless --all-layers."),
    ("vscreen window move --window ID [--to virtual|main|DISPLAYID] [--x X --y Y] [--fit]",
     "Move a window by AXPosition to X,Y points from the target display's top-left (default virtual, 40,40). --fit shrinks it to stay inside the display. Never raises or activates."),
    ("vscreen tree --pid P [--window ID] [--depth N] [--max-nodes N]",
     "Accessibility tree of the app's windows as JSON: path, role, title, value, description (aria-label), identifier, domIdentifier, frame, actions, children."),
    ("vscreen click --pid P (--path PATH | --match TERMS) [--window ID] [--action AXPress | --post]",
     "Perform an AX action on the element (default AXPress). --post sends mouse down/up at its centre to that pid only; the cursor does not move."),
    ("vscreen type --pid P (--path PATH | --match TERMS) [--window ID] --text T [--mode value|keys]",
     "value: set AXValue (replaces the text). keys: focus the element inside its app, then post Unicode key events to that pid only; fails with keys_not_routable when the app's focused element is another element."),
    ("vscreen key --pid P --key NAME [--mods cmd,shift,alt,ctrl] [--path PATH | --match TERMS]",
     "Post one key (return, tab, escape, delete, arrows, a-z, 0-9, ...) to that pid only, to its focused element; with an element, focus it first and fail with keys_not_routable if focus stays elsewhere."),
    ("vscreen shot [--display virtual|ID | --window ID] -o FILE.png [--scale 1|2] [--allow-main]",
     "Save a PNG of the virtual display (default) or one window. A target outside the virtual display needs --allow-main."),
    ("vscreen record [--display virtual|ID | --window ID] -o FILE.mov --duration SECONDS [--fps N] [--allow-main]",
     "Record a movie (H.264, no audio). Returns when the file is finalized; SIGINT/SIGTERM stop it early and cleanly."),
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

    func optionalInt(_ name: String, range: ClosedRange<Int>) throws -> Int? {
        guard values[name] != nil else { return nil }
        return try int(name, default: 0, range: range)
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
    case "shot": return try shot(Array(arguments.dropFirst()))
    case "record": return try record(Array(arguments.dropFirst()))
    case "window" where words.count > 1:
        let rest = Array(arguments.dropFirst(2))
        switch words[1] {
        case "list": return try windowList(rest)
        case "move": return try windowMove(rest)
        default: break
        }
    case "tree": return try tree(Array(arguments.dropFirst()))
    case "click": return try click(Array(arguments.dropFirst()))
    case "type": return try typeText(Array(arguments.dropFirst()))
    case "key": return try key(Array(arguments.dropFirst()))
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
