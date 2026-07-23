import Foundation

public enum ExportJSONEncoding: Sendable {
    /// Pretty-printed, sorted keys for share sheet, Coach handoff, clipboard.
    case humanReadable
    /// Minimal whitespace for webhook and Shortcut transmission.
    case compact

    public func configure(_ encoder: JSONEncoder) {
        encoder.dateEncodingStrategy = .iso8601
        switch self {
        case .humanReadable:
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        case .compact:
            encoder.outputFormatting = []
        }
    }
}

public enum SchemaV2Encoder {
    public static func encode(_ payload: ExportPayload, style: ExportJSONEncoding = .humanReadable) throws -> Data {
        let encoder = JSONEncoder()
        style.configure(encoder)
        return try encoder.encode(payload)
    }

    public static func encodeString(_ payload: ExportPayload, style: ExportJSONEncoding = .humanReadable) throws -> String {
        let data = try encode(payload, style: style)
        guard let string = String(data: data, encoding: .utf8) else {
            throw SchemaV2ExportError.encodingFailed
        }
        return string
    }
}

public enum SchemaV2ExportError: Error, Sendable, Equatable {
    case invalidWindow
    case encodingFailed
}
