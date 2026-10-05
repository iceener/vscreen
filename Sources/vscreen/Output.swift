import CoreGraphics
import Foundation

typealias JSONObject = [String: Any]

/// A failure with a stable `code` for agents and a human `message`. `details` carries what
/// already happened before the failure (plain JSON values only, so it is safe to send).
struct CLIError: Error, @unchecked Sendable {
    let code: String
    let message: String
    let details: JSONObject?

    init(_ code: String, _ message: String, details: JSONObject? = nil) {
        self.code = code
        self.message = message
        self.details = details
    }
}

func jsonData(_ object: JSONObject) -> Data {
    // JSONSerialization only fails on non-JSON types, which is a programming error here.
    try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
}

func emitSuccess(_ fields: JSONObject) -> Never {
    var object = fields
    object["ok"] = true
    FileHandle.standardOutput.write(jsonData(object) + Data("\n".utf8))
    exit(0)
}

func emitFailure(_ error: CLIError) -> Never {
    var fields: JSONObject = ["code": error.code, "message": error.message]
    if let details = error.details { fields["details"] = details }
    let object: JSONObject = ["ok": false, "error": fields]
    FileHandle.standardOutput.write(jsonData(object) + Data("\n".utf8))
    exit(1)
}

/// Human log line on stderr (the daemon's stderr is its log file).
func logLine(_ message: String) {
    let stamp = ISO8601DateFormatter().string(from: Date())
    FileHandle.standardError.write(Data("\(stamp) \(message)\n".utf8))
}

func rectJSON(_ rect: CGRect) -> JSONObject {
    ["x": Double(rect.origin.x), "y": Double(rect.origin.y), "width": Double(rect.width), "height": Double(rect.height)]
}

/// String from a NUL-terminated C buffer.
func stringFromCString(_ buffer: [CChar]) -> String {
    let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
    return String(decoding: bytes, as: UTF8.self)
}
