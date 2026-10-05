import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Element fields

/// Attributes read for every node. AXDOM* and AXDescription carry web content identity
/// (HTML id, class list, aria-label) in WebKit views such as Tauri apps.
private let nodeAttributes = [
    "AXRole", "AXSubrole", "AXRoleDescription", "AXTitle", "AXValue", "AXDescription", "AXIdentifier",
    "AXDOMIdentifier", "AXDOMClassList", "AXPlaceholderValue", "AXHelp", "AXURL", "AXEnabled", "AXFocused",
    "AXPosition", "AXSize",
]

let valueLimit = 200

/// One element's attributes as plain Swift values.
struct ElementFields {
    var values: [String: Any] = [:]
    var actions: [String] = []

    func string(_ attribute: String) -> String? { values[attribute] as? String }
    func bool(_ attribute: String) -> Bool? { values[attribute] as? Bool }

    var frame: CGRect? {
        guard let origin = values["AXPosition"] as? CGPoint, let size = values["AXSize"] as? CGSize else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// AXValue as text: strings as is, numbers and booleans formatted.
    var valueText: String? {
        switch values["AXValue"] {
        case let text as String: return text
        case let flag as Bool: return flag ? "true" : "false"
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }
}

/// CF attribute value as a plain value, or nil for types the JSON does not carry.
private func plain(_ value: CFTypeRef) -> Any? {
    let type = CFGetTypeID(value)
    switch type {
    case CFStringGetTypeID(): return value as? String
    case CFBooleanGetTypeID(): return CFBooleanGetValue((value as! CFBoolean))
    case CFNumberGetTypeID(): return value as? NSNumber
    case CFURLGetTypeID(): return (value as! URL).absoluteString
    case CFAttributedStringGetTypeID(): return (value as! NSAttributedString).string
    case CFArrayGetTypeID(): return (value as? [Any])?.compactMap { $0 as? String }
    case AXValueGetTypeID():
        let axValue = value as! AXValue
        switch AXValueGetType(axValue) {
        case .cgPoint:
            var point = CGPoint.zero
            return AXValueGetValue(axValue, .cgPoint, &point) ? point : nil
        case .cgSize:
            var size = CGSize.zero
            return AXValueGetValue(axValue, .cgSize, &size) ? size : nil
        default: return nil
        }
    default: return nil
    }
}

func readFields(_ element: AXUIElement) -> ElementFields {
    var fields = ElementFields()
    var raw: CFArray?
    if AXUIElementCopyMultipleAttributeValues(element, nodeAttributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw) == .success,
       let raw = raw as? [AnyObject], raw.count == nodeAttributes.count {
        for (name, value) in zip(nodeAttributes, raw) {
            if let converted = plain(value) { fields.values[name] = converted }
        }
    }
    var actions: CFArray?
    if AXUIElementCopyActionNames(element, &actions) == .success, let actions = actions as? [String] {
        fields.actions = actions
    }
    return fields
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
    return (value as? [AXUIElement]) ?? []
}

/// Node JSON without children; absent attributes are omitted.
func nodeJSON(_ fields: ElementFields, path: String) -> JSONObject {
    var node: JSONObject = ["path": path, "actions": fields.actions]
    let names: [(String, String)] = [
        ("role", "AXRole"), ("subrole", "AXSubrole"), ("roleDescription", "AXRoleDescription"), ("title", "AXTitle"),
        ("description", "AXDescription"), ("identifier", "AXIdentifier"), ("domIdentifier", "AXDOMIdentifier"),
        ("placeholder", "AXPlaceholderValue"), ("help", "AXHelp"), ("url", "AXURL"),
    ]
    for (key, attribute) in names {
        if let text = fields.string(attribute), !text.isEmpty { node[key] = text }
    }
    if let classes = fields.values["AXDOMClassList"] as? [String], !classes.isEmpty { node["domClassList"] = classes }
    if let value = fields.valueText {
        node["value"] = String(value.prefix(valueLimit))
        if value.count > valueLimit { node["valueTruncated"] = true }
    }
    if let enabled = fields.bool("AXEnabled") { node["enabled"] = enabled }
    if let focused = fields.bool("AXFocused") { node["focused"] = focused }
    if let frame = fields.frame { node["frame"] = rectJSON(frame) }
    return node
}

// MARK: - Paths

/// A window of the target app, addressed as `w<CGWindowID>` or, without an id, `n<index in AXWindows>`.
struct RootWindow {
    let element: AXUIElement
    let path: String
    let windowID: CGWindowID?
}

func rootWindows(pid: pid_t, windowID: Int?) throws -> [RootWindow] {
    let roots = axWindows(axApplication(pid)).enumerated().map { index, element in
        let id = axWindowID(element)
        return RootWindow(element: element, path: id.map { "w\($0)" } ?? "n\(index)", windowID: id)
    }
    if roots.isEmpty && NSRunningApplication(processIdentifier: pid) == nil {
        throw CLIError("app_not_found", "no running app with pid \(pid)")
    }
    guard let windowID else { return roots }
    guard let root = roots.first(where: { $0.windowID == CGWindowID(windowID) }) else {
        throw CLIError("window_not_found", "pid \(pid) has no AX window with id \(windowID)")
    }
    return [root]
}

/// A resolved element and how to address it again.
struct Target {
    let element: AXUIElement
    let path: String
    let root: RootWindow
    let fields: ElementFields
}

/// Resolves `w<id>/i/j/...` (or `n<index>/...`): child indices follow AXChildren order.
func resolvePath(pid: pid_t, path: String) throws -> Target {
    let parts = path.split(separator: "/").map(String.init)
    guard let head = parts.first else { throw CLIError("bad_arguments", "--path is empty") }
    let roots = try rootWindows(pid: pid, windowID: nil)
    guard let root = roots.first(where: { $0.path == head }) else {
        throw CLIError("element_not_found", "pid \(pid) has no window \(head); run `vscreen tree --pid \(pid)`")
    }
    var element = root.element
    for part in parts.dropFirst() {
        guard let index = Int(part), index >= 0 else { throw CLIError("bad_arguments", "bad path segment: \(part)") }
        let children = axChildren(element)
        guard index < children.count else {
            throw CLIError("element_not_found", "path \(path): segment \(part) is out of range (\(children.count) children)")
        }
        element = children[index]
    }
    return Target(element: element, path: path, root: root, fields: readFields(element))
}

// MARK: - Matching

/// One `key=value` (exact) or `key~value` (case-insensitive contains) term of `--match`.
struct MatchTerm: Equatable {
    let key: String
    let value: String
    let contains: Bool
}

let matchKeys: Set<String> = ["role", "subrole", "title", "id", "label", "value", "placeholder", "class"]

/// Parses `role=AXButton,title~save,id=fixture.text`. Values cannot contain commas.
func parseMatch(_ text: String) throws -> [MatchTerm] {
    let terms = try text.split(separator: ",").map { raw -> MatchTerm in
        guard let index = raw.firstIndex(where: { $0 == "=" || $0 == "~" }) else {
            throw CLIError("bad_arguments", "--match term \(raw) needs key=value or key~value")
        }
        let key = raw[..<index].trimmingCharacters(in: .whitespaces)
        guard matchKeys.contains(key) else {
            throw CLIError("bad_arguments", "--match key \(key) is not one of \(matchKeys.sorted().joined(separator: ", "))")
        }
        return MatchTerm(key: key, value: String(raw[raw.index(after: index)...]), contains: raw[index] == "~")
    }
    guard !terms.isEmpty else { throw CLIError("bad_arguments", "--match is empty") }
    return terms
}

/// Candidate strings an element offers for a match key. `id` covers AXIdentifier and the
/// HTML id (AXDOMIdentifier); `label` covers AXDescription (aria-label) and AXTitle.
func candidates(_ key: String, _ fields: ElementFields) -> [String] {
    switch key {
    case "role": return [fields.string("AXRole")].compactMap { $0 }
    case "subrole": return [fields.string("AXSubrole")].compactMap { $0 }
    case "title": return [fields.string("AXTitle")].compactMap { $0 }
    case "id": return [fields.string("AXIdentifier"), fields.string("AXDOMIdentifier")].compactMap { $0 }
    case "label": return [fields.string("AXDescription"), fields.string("AXTitle")].compactMap { $0 }
    case "value": return [fields.valueText].compactMap { $0 }
    case "placeholder": return [fields.string("AXPlaceholderValue")].compactMap { $0 }
    case "class": return (fields.values["AXDOMClassList"] as? [String]) ?? []
    default: return []
    }
}

func matches(_ terms: [MatchTerm], _ fields: ElementFields) -> Bool {
    terms.allSatisfy { term in
        candidates(term.key, fields).contains { text in
            term.contains ? text.localizedCaseInsensitiveContains(term.value) : text == term.value
        }
    }
}

let searchDepthLimit = 64
let searchNodeLimit = 20000

/// Depth-first search in AXChildren order over the roots; returns all matches, first first.
func search(_ roots: [RootWindow], terms: [MatchTerm]) -> (found: [Target], visited: Int) {
    var found: [Target] = []
    var visited = 0
    for root in roots {
        var stack: [(AXUIElement, String, Int)] = [(root.element, root.path, 0)]
        while let (element, path, depth) = stack.popLast(), visited < searchNodeLimit {
            visited += 1
            let fields = readFields(element)
            if matches(terms, fields) { found.append(Target(element: element, path: path, root: root, fields: fields)) }
            guard depth < searchDepthLimit else { continue }
            for (index, child) in axChildren(element).enumerated().reversed() {
                stack.append((child, "\(path)/\(index)", depth + 1))
            }
        }
    }
    return (found, visited)
}

// MARK: - tree

final class TreeWalker {
    let depthLimit: Int
    let nodeLimit: Int
    var count = 0
    var truncated = false

    init(depthLimit: Int, nodeLimit: Int) {
        self.depthLimit = depthLimit
        self.nodeLimit = nodeLimit
    }

    func node(_ element: AXUIElement, path: String, depth: Int) -> JSONObject {
        count += 1
        var node = nodeJSON(readFields(element), path: path)
        let children = axChildren(element)
        guard !children.isEmpty else { return node }
        guard depth < depthLimit, count < nodeLimit else {
            node["childCount"] = children.count
            truncated = true
            return node
        }
        var childNodes: [JSONObject] = []
        for (index, child) in children.enumerated() {
            guard count < nodeLimit else {
                truncated = true
                node["childCount"] = children.count
                break
            }
            childNodes.append(self.node(child, path: "\(path)/\(index)", depth: depth + 1))
        }
        node["children"] = childNodes
        return node
    }
}

func tree(_ arguments: [String]) throws -> JSONObject {
    let options = try Options(arguments, valueOptions: ["--pid", "--window", "--depth", "--max-nodes"], flagOptions: [])
    let pid = try requirePid(options)
    let windowID = try options.optionalInt("--window", range: 1...Int(UInt32.max))
    let walker = TreeWalker(depthLimit: try options.int("--depth", default: 30, range: 0...200),
                            nodeLimit: try options.int("--max-nodes", default: 5000, range: 1...100_000))
    try requireAccessibility()
    let roots = try rootWindows(pid: pid, windowID: windowID)
    let windows = roots.map { root -> JSONObject in
        var node = walker.node(root.element, path: root.path, depth: 0)
        if let id = root.windowID { node["windowID"] = Int(id) }
        return node
    }
    return ["pid": Int(pid), "windows": windows, "nodeCount": walker.count, "truncated": walker.truncated]
}

// MARK: - Shared element options

func requirePid(_ options: Options) throws -> pid_t {
    guard let pid = try options.optionalInt("--pid", range: 1...Int(Int32.max)) else {
        throw CLIError("bad_arguments", "--pid P is required")
    }
    return pid_t(pid)
}

/// Resolves `--path` or `--match` (optionally inside `--window`). Returns nil when neither is given.
func resolveElement(_ options: Options, pid: pid_t) throws -> (target: Target, matchCount: Int?)? {
    if let path = options.string("--path") {
        guard options.string("--match") == nil else { throw CLIError("bad_arguments", "use --path or --match, not both") }
        return (try resolvePath(pid: pid, path: path), nil)
    }
    guard let text = options.string("--match") else { return nil }
    let terms = try parseMatch(text)
    let roots = try rootWindows(pid: pid, windowID: try options.optionalInt("--window", range: 1...Int(UInt32.max)))
    var result = search(roots, terms: terms)
    if result.found.isEmpty {
        // WebKit builds a web view's AX tree only after the first AX request; look once more.
        settle(1)
        result = search(roots, terms: terms)
    }
    guard let first = result.found.first else {
        throw CLIError("element_not_found", "no element of pid \(pid) matches \(text) (\(result.visited) nodes searched)")
    }
    return (first, result.found.count)
}

func requireElement(_ options: Options, pid: pid_t) throws -> (target: Target, matchCount: Int?) {
    guard let resolved = try resolveElement(options, pid: pid) else {
        throw CLIError("bad_arguments", "--path PATH or --match TERMS is required")
    }
    return resolved
}

func elementJSON(_ resolved: (target: Target, matchCount: Int?)) -> JSONObject {
    var object = nodeJSON(resolved.target.fields, path: resolved.target.path)
    if let count = resolved.matchCount { object["matchCount"] = count }
    return object
}

/// Lets the target app process posted events and AX changes before reading them back.
func settle(_ seconds: Double = 0.25) {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: seconds))
}

func cursorLocation() -> CGPoint {
    CGEvent(source: nil)?.location ?? .zero
}

func pointJSON(_ point: CGPoint) -> JSONObject { ["x": Double(point.x), "y": Double(point.y)] }

// MARK: - click

func click(_ arguments: [String]) throws -> JSONObject {
    let options = try Options(arguments, valueOptions: ["--pid", "--path", "--match", "--window", "--action"], flagOptions: ["--post"])
    let pid = try requirePid(options)
    try requireAccessibility()
    let resolved = try requireElement(options, pid: pid)
    let target = resolved.target
    let before = focusSnapshot(pid: pid)
    var result: JSONObject = ["pid": Int(pid), "element": elementJSON(resolved)]

    if options.has("--post") {
        guard options.string("--action") == nil else { throw CLIError("bad_arguments", "use --action or --post, not both") }
        guard let frame = target.fields.frame else { throw CLIError("no_frame", "element \(target.path) has no AXPosition/AXSize") }
        let centre = CGPoint(x: frame.midX, y: frame.midY)
        let cursorBefore = cursorLocation()
        try postClick(pid: pid, at: centre, windowID: target.root.windowID)
        result["method"] = "post"
        result["point"] = pointJSON(centre)
        let during = focusSnapshot(pid: pid)
        settle()
        let cursorAfter = cursorLocation()
        result["cursorMoved"] = cursorBefore != cursorAfter
        result["focus"] = focusReport(before: before, during: during, after: focusSnapshot(pid: pid))
        return result
    }

    let action = options.string("--action") ?? "AXPress"
    guard target.fields.actions.contains(action) else {
        throw CLIError("action_unsupported", "element \(target.path) does not offer \(action); it offers \(target.fields.actions)")
    }
    let error = AXUIElementPerformAction(target.element, action as CFString)
    guard error == .success else { throw CLIError("ax_failed", "\(action) failed with AXError \(error.rawValue)") }
    let during = focusSnapshot(pid: pid)
    settle()
    result["method"] = "action"
    result["action"] = action
    result["focus"] = focusReport(before: before, during: during, after: focusSnapshot(pid: pid))
    return result
}

/// Mouse down/up delivered to `pid` only. The cursor does not move.
func postClick(pid: pid_t, at point: CGPoint, windowID: CGWindowID?) throws {
    let source = CGEventSource(stateID: .privateState)
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            throw CLIError("event_failed", "could not create a mouse event")
        }
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        if let windowID {
            event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
            event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        }
        event.postToPid(pid)
        usleep(30_000)
    }
}

// MARK: - type and key

/// Sets AXFocused on the element inside its app when it is not focused yet.
/// This moves keyboard focus within the target app only; it does not activate the app.
func focusInsideApp(_ target: Target) -> JSONObject {
    if target.fields.bool("AXFocused") == true { return ["needed": false] }
    let error = AXUIElementSetAttributeValue(target.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    settle(0.1)
    let now = readFields(target.element).bool("AXFocused")
    return ["needed": true, "attribute": "AXFocused", "axError": Int(error.rawValue), "focusedAfter": now ?? NSNull()]
}

/// Key events posted to an inactive app reach the first responder of the window AppKit treats
/// as focused, whatever window the event names. The app's AXFocusedUIElement is that element.
/// Fails with `keys_not_routable` instead of typing into another element.
func requireKeyRoute(_ target: Target, pid: pid_t) throws {
    var value: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(axApplication(pid), kAXFocusedUIElementAttribute as CFString, &value)
    let focused = error == .success ? value.map { $0 as! AXUIElement } : nil
    if let focused, CFEqual(focused, target.element) { return }
    let holder = focused.map { nodeJSON(readFields($0), path: "") }
    let description = holder.map { String(decoding: jsonData($0), as: UTF8.self) } ?? "none (AXError \(error.rawValue))"
    throw CLIError("keys_not_routable",
                   "key events for pid \(pid) would reach the app's focused element, not \(target.path); focused element: \(description). Use --mode value or an AX action.")
}

func typeText(_ arguments: [String]) throws -> JSONObject {
    let options = try Options(arguments, valueOptions: ["--pid", "--path", "--match", "--window", "--text", "--mode"], flagOptions: [])
    let pid = try requirePid(options)
    guard let text = options.string("--text") else { throw CLIError("bad_arguments", "--text T is required") }
    let mode = options.string("--mode") ?? "value"
    guard ["value", "keys"].contains(mode) else { throw CLIError("bad_arguments", "--mode must be value or keys") }
    try requireAccessibility()
    let resolved = try requireElement(options, pid: pid)
    let target = resolved.target
    let before = focusSnapshot(pid: pid)
    let valueBefore = target.fields.valueText
    var result: JSONObject = ["pid": Int(pid), "mode": mode, "element": elementJSON(resolved)]
    let during: FocusSnapshot

    if mode == "value" {
        var settable: DarwinBoolean = false
        AXUIElementIsAttributeSettable(target.element, kAXValueAttribute as CFString, &settable)
        var error = AXUIElementSetAttributeValue(target.element, kAXValueAttribute as CFString, text as CFString)
        settle(0.1)
        if error != .success || readFields(target.element).valueText != text {
            // Some controls take a value only while focused inside their app.
            result["focusInsideApp"] = focusInsideApp(target)
            error = AXUIElementSetAttributeValue(target.element, kAXValueAttribute as CFString, text as CFString)
        }
        during = focusSnapshot(pid: pid)
        result["settable"] = settable.boolValue
        result["axError"] = Int(error.rawValue)
    } else {
        result["focusInsideApp"] = focusInsideApp(target)
        try requireKeyRoute(target, pid: pid)
        try postText(text, pid: pid)
        during = focusSnapshot(pid: pid)
    }
    settle()
    let valueAfter = readFields(target.element).valueText
    result["valueBefore"] = valueBefore ?? NSNull()
    result["valueAfter"] = valueAfter ?? NSNull()
    result["changed"] = valueAfter != valueBefore
    if mode == "keys" && valueAfter == valueBefore {
        result["note"] = "the key events were posted to the app's focused element but the value did not change"
    }
    result["focus"] = focusReport(before: before, during: during, after: focusSnapshot(pid: pid))
    return result
}

/// One key down/up delivered to `pid` only. The cursor and the system key state do not change.
func postKey(pid: pid_t, code: CGKeyCode, characters: String?, flags: CGEventFlags) throws {
    let source = CGEventSource(stateID: .privateState)
    for down in [true, false] {
        guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else {
            throw CLIError("event_failed", "could not create a key event")
        }
        event.flags = flags
        if let characters {
            let units = Array(characters.utf16)
            event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
        }
        event.postToPid(pid)
    }
}

/// Unicode key events delivered to `pid` only, one key down/up per character.
func postText(_ text: String, pid: pid_t) throws {
    for character in text {
        try postKey(pid: pid, code: 0, characters: String(character), flags: [])
        usleep(10_000)
    }
}

/// US ANSI virtual key codes for `vscreen key --key`.
let keyCodes: [String: CGKeyCode] = {
    var codes: [String: CGKeyCode] = [
        "return": 36, "enter": 76, "tab": 48, "space": 49, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "forwarddelete": 117, "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
        "left": 123, "right": 124, "down": 125, "up": 126,
    ]
    let letters: [(Character, CGKeyCode)] = [
        ("a", 0), ("s", 1), ("d", 2), ("f", 3), ("h", 4), ("g", 5), ("z", 6), ("x", 7), ("c", 8), ("v", 9),
        ("b", 11), ("q", 12), ("w", 13), ("e", 14), ("r", 15), ("y", 16), ("t", 17), ("1", 18), ("2", 19),
        ("3", 20), ("4", 21), ("6", 22), ("5", 23), ("9", 25), ("7", 26), ("8", 28), ("0", 29), ("o", 31),
        ("u", 32), ("i", 34), ("p", 35), ("l", 37), ("j", 38), ("k", 40), ("n", 45), ("m", 46),
    ]
    for (character, code) in letters { codes[String(character)] = code }
    return codes
}()

let modifierFlags: [String: CGEventFlags] = [
    "cmd": .maskCommand, "command": .maskCommand, "shift": .maskShift, "alt": .maskAlternate,
    "option": .maskAlternate, "ctrl": .maskControl, "control": .maskControl, "fn": .maskSecondaryFn,
]

func parseModifiers(_ text: String?) throws -> CGEventFlags {
    var flags: CGEventFlags = []
    for name in (text ?? "").split(separator: ",").map({ $0.trimmingCharacters(in: .whitespaces).lowercased() }) {
        guard let flag = modifierFlags[name] else {
            throw CLIError("bad_arguments", "unknown modifier \(name); use cmd, shift, alt, ctrl, fn")
        }
        flags.insert(flag)
    }
    return flags
}

func key(_ arguments: [String]) throws -> JSONObject {
    let options = try Options(arguments, valueOptions: ["--pid", "--path", "--match", "--window", "--key", "--mods"], flagOptions: [])
    let pid = try requirePid(options)
    guard let name = options.string("--key")?.lowercased(), let code = keyCodes[name] else {
        throw CLIError("bad_arguments", "--key must be one of \(keyCodes.keys.sorted().joined(separator: ", "))")
    }
    let flags = try parseModifiers(options.string("--mods"))
    try requireAccessibility()
    let resolved = try resolveElement(options, pid: pid)
    let before = focusSnapshot(pid: pid)
    var result: JSONObject = ["pid": Int(pid), "key": name, "keyCode": Int(code)]
    if let resolved {
        result["element"] = elementJSON(resolved)
        result["focusInsideApp"] = focusInsideApp(resolved.target)
        try requireKeyRoute(resolved.target, pid: pid)
    }
    try postKey(pid: pid, code: code, characters: name.count == 1 ? name : nil, flags: flags)
    let during = focusSnapshot(pid: pid)
    settle()
    if let resolved { result["valueAfter"] = readFields(resolved.target.element).valueText ?? NSNull() }
    result["focus"] = focusReport(before: before, during: during, after: focusSnapshot(pid: pid))
    return result
}
