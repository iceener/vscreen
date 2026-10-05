// Test fixture: one window with a text field, a button, and a label that echoes clicks and text.
// It never activates itself: accessory policy, no activate call, the window is ordered back
// (never key, never front), and it refuses to open on the main display.
//
// Usage: vscreen-fixture --display <CGDirectDisplayID> [--x N] [--y N] [--title T] [--exit-after SECONDS]
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

        let screenNumber = window.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        emit([
            "event": "ready",
            "pid": Int(getpid()),
            "windowNumber": window.windowNumber,
            "displayID": Int(options.display),
            "screenDisplayID": screenNumber?.intValue ?? 0,
            "frame": ["x": Double(cgTopLeft.x), "y": Double(cgTopLeft.y),
                      "width": Double(frameSize.width), "height": Double(frameSize.height)],
            "isKey": window.isKeyWindow,
            "appActive": NSApp.isActive,
        ])
    }

    @objc func press() {
        clicks += 1
        label.stringValue = "clicks: \(clicks) text: \(field.stringValue)"
        emit(["event": "click", "count": clicks, "text": field.stringValue])
    }

    func controlTextDidChange(_ notification: Notification) {
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
