import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

// `vscreen shot` and `vscreen record`: PNG or movie of the virtual display or one window.
// Any target outside the virtual display needs --allow-main, so an agent never captures
// Adam's screen by accident.

private let captureFlagOptions: Set<String> = ["--allow-main"]
private let shotValueOptions: Set<String> = ["--display", "--window", "-o", "--scale"]
private let recordValueOptions: Set<String> = ["--display", "--window", "-o", "--duration", "--fps"]

/// What to capture, parsed and checked against the virtual display before any ScreenCaptureKit call.
private struct CaptureRequest: Sendable {
    enum Target: Sendable {
        case display(CGDirectDisplayID)
        case window(CGWindowID)
    }

    let target: Target
    let allowMain: Bool
    /// The running, online virtual display, if any.
    let virtualDisplayID: CGDirectDisplayID?

    init(_ options: Options) throws {
        allowMain = options.has("--allow-main")
        let status = displayStatus()
        if status["running"] as? Bool == true, let id = status["displayID"] as? Int {
            virtualDisplayID = CGDirectDisplayID(id)
        } else {
            virtualDisplayID = nil
        }
        switch (options.string("--display"), options.string("--window")) {
        case (.some, .some):
            throw CLIError("bad_arguments", "pass either --display or --window, not both")
        case (nil, .some(let raw)):
            guard let id = CGWindowID(raw) else { throw CLIError("bad_arguments", "--window must be a CGWindowID") }
            target = .window(id)
        case (let raw, nil):
            if raw == nil || raw == "virtual" {
                guard let virtualDisplayID else {
                    throw CLIError("display_not_running", "the virtual display is not running; run `vscreen display start`")
                }
                target = .display(virtualDisplayID)
            } else {
                guard let raw, let id = CGDirectDisplayID(raw) else {
                    throw CLIError("bad_arguments", "--display must be `virtual` or a display ID")
                }
                if id != virtualDisplayID && !allowMain {
                    throw CLIError("outside_virtual_display",
                                   "display \(id) is not the virtual display; pass --allow-main to capture it")
                }
                target = .display(id)
            }
        }
    }
}

/// A resolved ScreenCaptureKit filter plus the JSON that describes it.
private struct ResolvedTarget {
    let filter: SCContentFilter
    let json: JSONObject
}

private func resolve(_ request: CaptureRequest) async throws -> ResolvedTarget {
    let content: SCShareableContent
    do {
        content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
    } catch {
        throw CLIError("capture_failed", "SCShareableContent: \(error.localizedDescription)")
    }
    switch request.target {
    case .display(let id):
        guard let display = content.displays.first(where: { $0.displayID == id }) else {
            throw CLIError("display_not_found", "display \(id) is not online")
        }
        return ResolvedTarget(
            filter: SCContentFilter(display: display, excludingWindows: []),
            json: [
                "kind": "display",
                "displayID": Int(id),
                "virtual": id == request.virtualDisplayID,
                "frame": rectJSON(display.frame),
            ])
    case .window(let id):
        guard let window = content.windows.first(where: { $0.windowID == id }) else {
            throw CLIError("window_not_found", "window \(id) does not exist")
        }
        let onVirtual = request.virtualDisplayID.map { CGDisplayBounds($0).contains(window.frame) } ?? false
        if !onVirtual && !request.allowMain {
            throw CLIError("outside_virtual_display",
                           "window \(id) at \(describe(window.frame)) is not inside the virtual display; pass --allow-main to capture it")
        }
        var json: JSONObject = [
            "kind": "window",
            "windowID": Int(id),
            "onVirtualDisplay": onVirtual,
            "frame": rectJSON(window.frame),
            "title": window.title ?? "",
        ]
        if let app = window.owningApplication {
            json["pid"] = Int(app.processID)
            json["bundleId"] = app.bundleIdentifier
        }
        return ResolvedTarget(filter: SCContentFilter(desktopIndependentWindow: window), json: json)
    }
}

// MARK: - Shared helpers

/// Screen Recording preflight that never prompts; must run before any ScreenCaptureKit call.
private func preflightScreenRecording() throws {
    guard CGPreflightScreenCaptureAccess() else {
        throw CLIError("permission_missing", "Screen Recording is not granted to vscreen; run `vscreen permissions request` yourself")
    }
}

private func outputURL(_ options: Options) throws -> URL {
    guard let path = options.string("-o"), !path.isEmpty else { throw CLIError("bad_arguments", "-o FILE is required") }
    let url = URL(fileURLWithPath: path).standardizedFileURL
    var isDirectory: ObjCBool = false
    let parent = url.deletingLastPathComponent().path
    guard FileManager.default.fileExists(atPath: parent, isDirectory: &isDirectory), isDirectory.boolValue else {
        throw CLIError("output_failed", "directory \(parent) does not exist")
    }
    return url
}

/// Pixel size of `filter`'s content at `scale` pixels per point.
private func pixelSize(_ filter: SCContentFilter, scale: Double) -> (width: Int, height: Int) {
    (Int((filter.contentRect.width * scale).rounded()), Int((filter.contentRect.height * scale).rounded()))
}

private final class ResultBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Result<T, Error>?

    var value: Result<T, Error>? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Runs `body` to completion from synchronous code, keeping the main run loop serviced.
private func runBlocking<T>(_ body: @escaping @Sendable () async throws -> T) throws -> T {
    let box = ResultBox<T>()
    Task.detached {
        do { box.value = .success(try await body()) } catch { box.value = .failure(error) }
    }
    while true {
        if let result = box.value { return try result.get() }
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
    }
}

// MARK: - shot

func shot(_ arguments: [String]) throws -> JSONObject {
    let options = try Options(arguments, valueOptions: shotValueOptions, flagOptions: captureFlagOptions)
    let output = try outputURL(options)
    var scale: Double?
    if let raw = options.string("--scale") {
        guard raw == "1" || raw == "2" else { throw CLIError("bad_arguments", "--scale must be 1 or 2") }
        scale = Double(raw)
    }
    try preflightScreenRecording()
    let request = try CaptureRequest(options)
    return try runBlocking { [scale] in
        let target = try await resolve(request)
        let pointScale = scale ?? Double(target.filter.pointPixelScale)
        let size = pixelSize(target.filter, scale: pointScale)
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.showsCursor = false
        let image: CGImage
        do {
            image = try await SCScreenshotManager.captureImage(contentFilter: target.filter, configuration: configuration)
        } catch {
            throw CLIError("capture_failed", "SCScreenshotManager: \(error.localizedDescription)")
        }
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil) else {
            throw CLIError("output_failed", "cannot write \(output.path)")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CLIError("output_failed", "cannot write \(output.path)") }
        return [
            "path": output.path,
            "pixels": ["width": image.width, "height": image.height],
            "scale": pointScale,
            "target": target.json,
        ]
    }
}

// MARK: - record

/// Resolves once with the first stop reason: the duration timer or SIGINT/SIGTERM.
private final class StopGate: @unchecked Sendable {
    private let lock = NSLock()
    private var reason: String?
    private var waiter: CheckedContinuation<String, Never>?
    private var sources: [DispatchSourceSignal] = []

    /// Installs SIGINT/SIGTERM handlers before capture starts, so a signal always stops cleanly.
    init() {
        for (number, name) in [(SIGINT, "SIGINT"), (SIGTERM, "SIGTERM")] {
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
            source.setEventHandler { [weak self] in self?.stop(name) }
            source.resume()
            sources.append(source)
        }
    }

    func stop(_ why: String) {
        let continuation: CheckedContinuation<String, Never>? = lock.withLock {
            guard reason == nil else { return nil }
            reason = why
            defer { waiter = nil }
            return waiter
        }
        continuation?.resume(returning: why)
    }

    /// Waits up to `seconds`; returns early when a signal arrives.
    func wait(seconds: Double) async -> String {
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in self?.stop("duration") }
        return await withCheckedContinuation { continuation in
            let done: String? = lock.withLock {
                if let reason { return reason }
                waiter = continuation
                return nil
            }
            if let done { continuation.resume(returning: done) }
        }
    }
}

/// Reports when SCRecordingOutput has finalized the movie file, or failed.
private final class RecordingObserver: NSObject, SCRecordingOutputDelegate, SCStreamDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var outcome: Result<Void, CLIError>?
    private var waiter: CheckedContinuation<Void, Error>?

    private func finish(_ result: Result<Void, CLIError>) {
        let continuation: CheckedContinuation<Void, Error>? = lock.withLock {
            guard outcome == nil else { return nil }
            outcome = result
            defer { waiter = nil }
            return waiter
        }
        continuation?.resume(with: result.mapError { $0 as Error })
    }

    var failure: CLIError? {
        lock.withLock {
            if case .failure(let error) = outcome { return error }
            return nil
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) { finish(.success(())) }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        finish(.failure(CLIError("capture_failed", "SCRecordingOutput: \(error.localizedDescription)")))
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        finish(.failure(CLIError("capture_failed", "SCStream stopped: \(error.localizedDescription)")))
    }

    func finished() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let done: Result<Void, CLIError>? = lock.withLock {
                if let outcome { return outcome }
                waiter = continuation
                return nil
            }
            if let done { continuation.resume(with: done.mapError { $0 as Error }) }
        }
    }
}

func record(_ arguments: [String]) throws -> JSONObject {
    let options = try Options(arguments, valueOptions: recordValueOptions, flagOptions: captureFlagOptions)
    let output = try outputURL(options)
    guard let rawDuration = options.string("--duration"), let duration = Double(rawDuration),
          duration > 0, duration <= 3600 else {
        throw CLIError("bad_arguments", "--duration SECONDS is required, greater than 0 and at most 3600")
    }
    let fps = try options.int("--fps", default: 30, range: 1...60)
    try preflightScreenRecording()
    let request = try CaptureRequest(options)
    let gate = StopGate()
    return try runBlocking {
        let target = try await resolve(request)
        let scale = Double(target.filter.pointPixelScale)
        let size = pixelSize(target.filter, scale: scale)
        let configuration = SCStreamConfiguration()
        configuration.width = size.width
        configuration.height = size.height
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        configuration.showsCursor = false

        let recordingConfiguration = SCRecordingOutputConfiguration()
        recordingConfiguration.outputURL = output
        recordingConfiguration.outputFileType = .mov
        recordingConfiguration.videoCodecType = .h264
        try? FileManager.default.removeItem(at: output)

        let observer = RecordingObserver()
        let recording = SCRecordingOutput(configuration: recordingConfiguration, delegate: observer)
        let stream = SCStream(filter: target.filter, configuration: configuration, delegate: observer)
        do {
            try stream.addRecordingOutput(recording)
            try await stream.startCapture()
        } catch {
            throw CLIError("capture_failed", "SCStream start: \(error.localizedDescription)")
        }
        let started = Date()
        let stoppedBy = await gate.wait(seconds: duration)
        if let failure = observer.failure { throw failure }
        do {
            try await stream.stopCapture()
        } catch {
            throw CLIError("capture_failed", "SCStream stop: \(error.localizedDescription)")
        }
        try await observer.finished()
        let elapsed = Date().timeIntervalSince(started)

        let movieDuration = try? await AVURLAsset(url: output).load(.duration)
        return [
            "path": output.path,
            "pixels": ["width": size.width, "height": size.height],
            "scale": scale,
            "fps": fps,
            "durationRequested": duration,
            "duration": milliseconds(movieDuration?.seconds ?? recording.recordedDuration.seconds),
            "elapsed": milliseconds(elapsed),
            "stoppedBy": stoppedBy,
            "target": target.json,
        ]
    }
}

private func milliseconds(_ seconds: Double) -> Double { (seconds * 1000).rounded() / 1000 }

/// `x,y WxH` in global points, for error messages.
private func describe(_ rect: CGRect) -> String {
    "\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height))"
}
