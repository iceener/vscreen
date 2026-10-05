// Test fixture: one window with a text field, a button, and a label that echoes clicks and text.
// It never activates itself: accessory policy, no activate call, the window is ordered back
// (never key, never front), and it refuses to open on the main display.
// With --main-window 1 it adds a second, small window near the main display's bottom-right
// corner, also ordered back behind every other window: the target for `vscreen window move`.
//
// Usage: vscreen-fixture --display <CGDirectDisplayID> [--x N] [--y N] [--title T] [--exit-after SECONDS] [--main-window 1]
// --x/--y are points from the display's top-left corner. Events print as JSON lines on stdout.
import AppKit

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    FileHandle.standardOutput.write(data + Data("\n".utf8))
}

func fail(_ code: String, _ message: String) -> Never {
    emit(["ok": false, "error": ["code": code, "message": message]])
    exit(1)
}

struct FixtureOptions {
    var display: CGDirectDisplayID = 0
    var x: Double = 40
    var y: Double = 40
    var title = "vscreen fixture"
    var exitAfter: Double = 600
    var mainWindow = false

    init(_ arguments: [String]) {
        var index = 0
        while index < arguments.count {
            guard index + 1 < arguments.count else { fail("bad_arguments", "\(arguments[index]) needs a value") }
            let value = arguments[index + 1]
            switch arguments[index] {
            case "--display": display = CGDirectDisplayID(value) ?? 0
            case "--x": x = Double(value) ?? x
            case "--y": y = Double(value) ?? y
            case "--title": title = value
            case "--exit-after": exitAfter = Double(value) ?? exitAfter
            case "--main-window": mainWindow = value == "1"
            default: fail("bad_arguments", "unknown argument: \(arguments[index])")
            }
            index += 2
        }
    }
}

@MainActor
final class Fixture: NSObject, NSApplicationDelegate, NSTextFieldDelegate {
    let options: FixtureOptions
    var window: NSWindow?
    var mainWindow: NSWindow?
    var lastValue = ""
    let field = NSTextField(string: "")
    let label = NSTextField(labelWithString: "clicks: 0")
    var clicks = 0

    init(_ options: FixtureOptions) {
        self.options = options
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 420, height: 150)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable],
                              backing: .buffered, defer: false)
        window.title = options.title
        window.isReleasedWhenClosed = false

        field.frame = NSRect(x: 20, y: 95, width: 380, height: 24)
        field.placeholderString = "type here"
        field.delegate = self
        field.setAccessibilityIdentifier("fixture.text")

        let button = NSButton(title: "Press", target: self, action: #selector(press))
        button.frame = NSRect(x: 20, y: 52, width: 100, height: 30)
        button.setAccessibilityIdentifier("fixture.button")

        label.frame = NSRect(x: 20, y: 18, width: 380, height: 22)
        label.setAccessibilityIdentifier("fixture.label")

        window.contentView?.addSubview(field)
        window.contentView?.addSubview(button)
        window.contentView?.addSubview(label)

        // CG global space is top-left based; Cocoa is bottom-left of the primary display.
        let display = CGDisplayBounds(options.display)
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        let cgTopLeft = CGPoint(x: display.minX + options.x, y: display.minY + options.y)
        window.setFrameOrigin(NSPoint(x: cgTopLeft.x, y: primaryHeight - cgTopLeft.y - frameSize.height))
        window.orderBack(nil)
        self.window = window
        let mainWindow = options.mainWindow ? makeMainWindow() : nil

        // Evidence for focus checks: any key-window or activation change prints an event.
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                     NSApplication.didBecomeActiveNotification, NSApplication.didResignActiveNotification] {
            center.addObserver(self, selector: #selector(focusChanged(_:)), name: name, object: nil)
        }
        // AXValue writes bypass the field editor and its delegate; a poll makes them visible.
        Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { self.pollValue() }
        }

        let screenNumber = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        var ready: [String: Any] = [
            "event": "ready",
            "pid": Int(getpid()),
            "windowNumber": window.windowNumber,
            "displayID": Int(options.display),
            "screenDisplayID": screenNumber?.intValue ?? 0,
            "frame": ["x": Double(cgTopLeft.x), "y": Double(cgTopLeft.y),
                      "width": Double(frameSize.width), "height": Double(frameSize.height)],
            "isKey": window.isKeyWindow,
            "appActive": NSApp.isActive,
        ]
        if let mainWindow { ready["mainWindowNumber"] = mainWindow.windowNumber }
        emit(ready)
    }

    /// A small window near the main display's bottom-right corner, behind every other window.
    func makeMainWindow() -> NSWindow {
        let size = NSSize(width: 300, height: 80)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "\(options.title) (main)"
        window.isReleasedWhenClosed = false
        let note = NSTextField(labelWithString: "vscreen fixture: move target")
        note.frame = NSRect(x: 20, y: 30, width: 260, height: 22)
        note.setAccessibilityIdentifier("fixture.main.label")
        window.contentView?.addSubview(note)
        // Cocoa origin of the primary display is its bottom-left corner.
        let main = CGDisplayBounds(CGMainDisplayID())
        let frameSize = window.frameRect(forContentRect: NSRect(origin: .zero, size: size)).size
        window.setFrameOrigin(NSPoint(x: main.maxX - frameSize.width - 60, y: 120))
        window.orderBack(nil)
        mainWindow = window
        return window
    }

    func pollValue() {
        guard field.stringValue != lastValue else { return }
        lastValue = field.stringValue
        label.stringValue = "clicks: \(clicks) text: \(field.stringValue)"
        emit(["event": "value", "text": field.stringValue])
    }

    @objc func focusChanged(_ note: Notification) {
        var event: [String: Any] = ["event": note.name.rawValue]
        if let window = note.object as? NSWindow { event["windowNumber"] = window.windowNumber }
        emit(event)
    }

    @objc func press() {
        clicks += 1
        label.stringValue = "clicks: \(clicks) text: \(field.stringValue)"
        emit(["event": "click", "count": clicks, "text": field.stringValue])
    }

    /// Field-editor input (typed keys). AXValue writes show up as `value` events instead.
    func controlTextDidChange(_ notification: Notification) {
        lastValue = field.stringValue
        label.stringValue = "clicks: \(clicks) text: \(field.stringValue)"
        emit(["event": "text", "text": field.stringValue])
    }
}

let options = FixtureOptions(Array(CommandLine.arguments.dropFirst()))
var displayCount: UInt32 = 0
var displays = [CGDirectDisplayID](repeating: 0, count: 16)
CGGetOnlineDisplayList(16, &displays, &displayCount)
guard options.display != 0, displays.prefix(Int(displayCount)).contains(options.display) else {
    fail("display_not_found", "--display must name an online display (see `vscreen display status`)")
}
guard options.display != CGMainDisplayID() else {
    fail("main_display_refused", "the fixture never opens on the main display")
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let fixture = Fixture(options)
app.delegate = fixture
if options.exitAfter > 0 {
    DispatchQueue.main.asyncAfter(deadline: .now() + options.exitAfter) { exit(0) }
}
app.run()
