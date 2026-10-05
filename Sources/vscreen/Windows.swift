import AppKit
import ApplicationServices
import CPrivate
import CoreGraphics
import Foundation

// MARK: - Window list

/// One CGWindowList entry with the fields agents filter and address by.
struct WindowInfo {
    let id: CGWindowID
    let pid: pid_t
    let app: String
    let bundleId: String
    let title: String
    let frame: CGRect
    let layer: Int
    let onScreen: Bool
    /// Front-to-back index among on-screen windows; nil when off screen.
    let order: Int?
    let displayID: CGDirectDisplayID?
}

/// The online display that holds most of `rect`, or nil when it is on no display.
func displayHolding(_ rect: CGRect) -> CGDirectDisplayID? {
    var best: (id: CGDirectDisplayID, area: CGFloat)?
    for id in onlineDisplays() {
        let overlap = CGDisplayBounds(id).intersection(rect)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { continue }
        let area = overlap.width * overlap.height
        if best == nil || area > best!.area { best = (id, area) }
    }
    return best?.id
}

/// The virtual display id from the daemon state, when that display is online.
func virtualDisplayID() -> CGDirectDisplayID? {
    guard let id = readState()?["displayID"] as? Int else { return nil }
    let displayID = CGDirectDisplayID(id)
    return onlineDisplays().contains(displayID) ? displayID : nil
}

/// Resolves `virtual`, `main`, or a numeric CGDirectDisplayID to an online display.
func resolveDisplay(_ name: String) throws -> CGDirectDisplayID {
    switch name {
    case "virtual":
        guard let id = virtualDisplayID() else {
            throw CLIError("display_not_running", "the virtual display is not online; run `vscreen display start`")
        }
        return id
    case "main":
        return CGMainDisplayID()
    default:
        guard let raw = UInt32(name), onlineDisplays().contains(raw) else {
            throw CLIError("display_not_found", "--display/--to must be virtual, main, or an online display id")
        }
        return raw
    }
}

/// All windows known to the window server, front to back.
func windowInfos() -> [WindowInfo] {
    let all = (CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    let onScreen = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
    var order: [CGWindowID: Int] = [:]
    for (index, entry) in onScreen.enumerated() {
        if let id = entry[kCGWindowNumber as String] as? Int { order[CGWindowID(id)] = index }
    }
    var bundles: [pid_t: String] = [:]
    return all.compactMap { entry in
        guard let rawID = entry[kCGWindowNumber as String] as? Int,
              let rawPid = entry[kCGWindowOwnerPID as String] as? Int else { return nil }
        let id = CGWindowID(rawID)
        let pid = pid_t(rawPid)
        var frame = CGRect.null
        if let bounds = entry[kCGWindowBounds as String] as? NSDictionary {
            frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) ?? .null
        }
        if bundles[pid] == nil {
            bundles[pid] = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? ""
        }
        return WindowInfo(
            id: id, pid: pid,
            app: entry[kCGWindowOwnerName as String] as? String ?? "",
            bundleId: bundles[pid] ?? "",
            title: entry[kCGWindowName as String] as? String ?? "",
            frame: frame,
            layer: entry[kCGWindowLayer as String] as? Int ?? 0,
            onScreen: entry[kCGWindowIsOnscreen as String] as? Bool ?? false,
            order: order[id],
            displayID: frame.isNull ? nil : displayHolding(frame))
    }
}

func windowJSON(_ window: WindowInfo, virtualID: CGDirectDisplayID?) -> JSONObject {
    var object: JSONObject = [
        "id": Int(window.id), "pid": Int(window.pid), "app": window.app, "bundleId": window.bundleId,
        "title": window.title, "layer": window.layer, "onScreen": window.onScreen,
        "frame": window.frame.isNull ? NSNull() : rectJSON(window.frame),
        "display": window.displayID.map { Int($0) } ?? NSNull(),
        "onVirtualDisplay": window.displayID != nil && window.displayID == virtualID,
    ]
    if let order = window.order { object["order"] = order }
    return object
}

func windowList(_ arguments: [String]) throws -> JSONObject {
    let options = try Options(arguments, valueOptions: ["--pid", "--app", "--bundle", "--display"], flagOptions: ["--all-layers"])
    let pid = try options.optionalInt("--pid", range: 1...Int(Int32.max))
    let display = try options.string("--display").map(resolveDisplay)
    let app = options.string("--app")?.lowercased()
    let bundle = options.string("--bundle")
    let virtualID = virtualDisplayID()
    let windows = windowInfos().filter { window in
        (options.has("--all-layers") || window.layer == 0)
            && (pid == nil || window.pid == pid_t(pid!))
            && (app == nil || window.app.lowercased() == app)
            && (bundle == nil || window.bundleId == bundle)
            && (display == nil || window.displayID == display)
    }
    return [
        "windows": windows.map { windowJSON($0, virtualID: virtualID) },
        "virtualDisplay": virtualID.map { Int($0) } ?? NSNull(),
        "mainDisplay": Int(CGMainDisplayID()),
    ]
}

// MARK: - AX window lookup

/// Fails with `permission_missing` before any AX call when vscreen lacks Accessibility.
func requireAccessibility() throws {
    guard AXIsProcessTrusted() else {
        throw CLIError("permission_missing", "vscreen lacks Accessibility; run `vscreen permissions request` and allow vscreen")
    }
}

func axApplication(_ pid: pid_t) -> AXUIElement {
    let app = AXUIElementCreateApplication(pid)
    AXUIElementSetMessagingTimeout(app, 3)
    return app
}

func axWindowID(_ element: AXUIElement) -> CGWindowID? {
    var id: CGWindowID = 0
    return _AXUIElementGetWindow(element, &id) == .success && id != 0 ? id : nil
}

func axWindows(_ app: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success else { return [] }
    return (value as? [AXUIElement]) ?? []
}

func axPoint(_ element: AXUIElement, _ attribute: String) -> CGPoint? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var point = CGPoint.zero
    return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
}

func axSize(_ element: AXUIElement, _ attribute: String) -> CGSize? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value,
          CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
    var size = CGSize.zero
    return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    guard let origin = axPoint(element, kAXPositionAttribute), let size = axSize(element, kAXSizeAttribute) else { return nil }
    return CGRect(origin: origin, size: size)
}

/// How the AX window for a CGWindowID was found.
enum WindowMatch: String {
    case windowID
    case frame
}

/// The AX window element for `window`: by `_AXUIElementGetWindow`, else by identical frame.
func axWindow(for window: WindowInfo) -> (element: AXUIElement, match: WindowMatch)? {
    let candidates = axWindows(axApplication(window.pid))
    if let element = candidates.first(where: { axWindowID($0) == window.id }) { return (element, .windowID) }
    let byFrame = candidates.filter { axFrame($0) == window.frame }
    return byFrame.count == 1 ? (byFrame[0], .frame) : nil
}

func findWindow(_ id: Int) throws -> WindowInfo {
    guard let window = windowInfos().first(where: { Int($0.id) == id }) else {
        throw CLIError("window_not_found", "no window with id \(id); see `vscreen window list`")
    }
    return window
}

// MARK: - Window move

/// Top-left origin of a window placed at `offset` inside `display`; with `fit`, the size
/// shrinks so the window stays inside the display. Pure geometry.
func placement(window size: CGSize, display: CGRect, offset: CGPoint, fit: Bool) -> (origin: CGPoint, size: CGSize?) {
    let origin = CGPoint(x: display.minX + offset.x, y: display.minY + offset.y)
    guard fit else { return (origin, nil) }
    let fitted = CGSize(width: min(size.width, display.maxX - origin.x), height: min(size.height, display.maxY - origin.y))
    return (origin, fitted == size ? nil : fitted)
}

func setAX(_ element: AXUIElement, _ attribute: String, point: CGPoint) -> AXError {
    var value = point
    guard let axValue = AXValueCreate(.cgPoint, &value) else { return .failure }
    return AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
}

func setAX(_ element: AXUIElement, _ attribute: String, size: CGSize) -> AXError {
    var value = size
    guard let axValue = AXValueCreate(.cgSize, &value) else { return .failure }
    return AXUIElementSetAttributeValue(element, attribute as CFString, axValue)
}

func windowMove(_ arguments: [String]) throws -> JSONObject {
    let options = try Options(arguments, valueOptions: ["--window", "--to", "--x", "--y"], flagOptions: ["--fit"])
    guard let id = try options.optionalInt("--window", range: 1...Int(UInt32.max)) else {
        throw CLIError("bad_arguments", "window move needs --window ID")
    }
    let offset = CGPoint(x: try options.int("--x", default: 40, range: 0...20000),
                         y: try options.int("--y", default: 40, range: 0...20000))
    try requireAccessibility()
    let target = try resolveDisplay(options.string("--to") ?? "virtual")
    let window = try findWindow(id)
    let before = focusSnapshot(pid: window.pid)
    guard let (element, match) = axWindow(for: window) else {
        throw CLIError("ax_window_not_found",
                       "no AX window of pid \(window.pid) matches window \(id) (by id or frame); a window on another Space may be missing from AXWindows (onScreen: \(window.onScreen))")
    }
    let displayFrame = CGDisplayBounds(target)
    let plan = placement(window: window.frame.size, display: displayFrame, offset: offset, fit: options.has("--fit"))

    // Move first, then shrink on the target display; a resize can shift the origin, so move again.
    var positionError = setAX(element, kAXPositionAttribute, point: plan.origin)
    var sizeError: AXError?
    if let size = plan.size {
        sizeError = setAX(element, kAXSizeAttribute, size: size)
        positionError = setAX(element, kAXPositionAttribute, point: plan.origin)
    }
    let during = focusSnapshot(pid: window.pid)

    // The window server reports the new frame a moment after the AX call returns.
    var moved = window
    for _ in 0..<20 {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        moved = try findWindow(id)
        if moved.frame.origin == plan.origin { break }
    }
    guard positionError == .success else {
        throw CLIError("ax_failed", "setting AXPosition failed with AXError \(positionError.rawValue)")
    }
    let after = focusSnapshot(pid: window.pid)
    let virtualID = virtualDisplayID()
    var result: JSONObject = [
        "window": windowJSON(moved, virtualID: virtualID),
        "before": windowJSON(window, virtualID: virtualID),
        "to": ["display": Int(target), "frame": rectJSON(displayFrame)],
        "requested": ["x": Double(plan.origin.x), "y": Double(plan.origin.y)],
        "axWindowMatch": match.rawValue,
        "arrived": moved.displayID == target,
        "focus": focusReport(before: before, during: during, after: after),
    ]
    if let size = plan.size {
        result["resized"] = ["width": Double(size.width), "height": Double(size.height),
                             "ok": sizeError == .success]
    }
    return result
}

// MARK: - Focus evidence

/// Frontmost app and whether the target pid is active, read fresh.
struct FocusSnapshot {
    let frontmost: JSONObject
    let targetActive: Bool
}

/// NSWorkspace caches the frontmost app and updates it from run-loop notifications;
/// a short run-loop turn makes the value current for this process.
func focusSnapshot(pid: pid_t) -> FocusSnapshot {
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    let front = frontmostAppJSON()
    return FocusSnapshot(frontmost: front, targetActive: front["pid"] as? Int == Int(pid))
}

func focusReport(before: FocusSnapshot, during: FocusSnapshot, after: FocusSnapshot) -> JSONObject {
    let unchanged = NSDictionary(dictionary: before.frontmost).isEqual(to: during.frontmost)
        && NSDictionary(dictionary: during.frontmost).isEqual(to: after.frontmost)
    return [
        "frontmostBefore": before.frontmost,
        "frontmostDuring": during.frontmost,
        "frontmostAfter": after.frontmost,
        "frontmostUnchanged": unchanged,
        "targetActiveBefore": before.targetActive,
        "targetBecameFrontmost": !before.targetActive && (during.targetActive || after.targetActive),
    ]
}
