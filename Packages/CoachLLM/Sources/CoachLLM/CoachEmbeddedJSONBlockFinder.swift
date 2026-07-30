import Foundation

public enum CoachEmbeddedJSONBlockFinder: Sendable {
    public static func blocks(in text: String) -> [String] {
        var results: [String] = []
        let scalars = Array(text.unicodeScalars)
        var index = 0
        while index < scalars.count {
            guard scalars[index] == "{" else {
                index += 1
                continue
            }
            guard let end = closingBraceIndex(in: scalars, opening: index) else {
                index += 1
                continue
            }
            let startScalar = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: index)
            let endScalar = text.unicodeScalars.index(text.unicodeScalars.startIndex, offsetBy: end)
            results.append(String(text.unicodeScalars[startScalar ... endScalar]))
            index = end + 1
        }
        return results
    }

    public static func firstBlock(
        in text: String,
        matching schema: CoachOutputSchemaVersion
    ) -> String? {
        for block in blocks(in: text) {
            let sanitized = CoachJSONSanitizer.sanitize(block)
            guard let data = sanitized.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let version = object["schemaVersion"] as? String,
                  version == schema.rawValue
            else {
                continue
            }
            return sanitized
        }
        return nil
    }

    private static func closingBraceIndex(in scalars: [UnicodeScalar], opening: Int) -> Int? {
        var depth = 0
        var inString = false
        var isEscaped = false
        var index = opening
        while index < scalars.count {
            let scalar = scalars[index]
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if scalar == "\\" {
                    isEscaped = true
                } else if scalar == "\"" {
                    inString = false
                }
            } else if scalar == "\"" {
                inString = true
            } else if scalar == "{" {
                depth += 1
            } else if scalar == "}" {
                depth -= 1
                if depth == 0 {
                    return index
                }
            }
            index += 1
        }
        return nil
    }
}
