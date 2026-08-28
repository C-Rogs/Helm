import Foundation

/// Pulls from/to lift names and relative moves out of athlete wording so the
/// app can match against the live session and picker instead of trusting model IDs.
enum SessionSwapPhrase: Sendable {
    struct Swap: Sendable, Equatable {
        let from: String
        let to: String
    }

    struct Move: Sendable, Equatable {
        enum Position: Sendable, Equatable {
            case start
            case end
        }

        /// Nil or "it" / "that" means the latest swap target.
        let target: String?
        let position: Position
    }

    static func parse(_ text: String) -> Swap? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            #"(?i)(?:swap(?:\s+out)?|switch(?:\s+out)?|replace|change)\s+(.+?)\s+(?:for|with|to)\s+(.+?)(?:\s+and\b.*)?$"#,
            #"(?i)(.+?)\s+instead of\s+(.+?)(?:\s+and\b.*)?$"#,
            #"(?i)instead of\s+(.+?)[,\s]+(?:do|use|swap in)\s+(.+?)(?:\s+and\b.*)?$"#,
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(trimmed.startIndex..., in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range),
                  match.numberOfRanges >= 3,
                  let fromRange = Range(match.range(at: 1), in: trimmed),
                  let toRange = Range(match.range(at: 2), in: trimmed)
            else { continue }

            var from = sanitize(String(trimmed[fromRange]))
            var to = sanitize(String(trimmed[toRange]))
            if index == 1 {
                swap(&from, &to)
            }
            let fromIsPronoun = isPronoun(from)
            if (from.count >= 3 || fromIsPronoun), to.count >= 3, from.lowercased() != to.lowercased() {
                return Swap(from: from, to: to)
            }
        }
        return nil
    }

    /// "add rope hammer curl" / "include face pull". Used so athlete wording
    /// is tried as a catalog phrase before a wrong toExerciseID.
    static func parseAdd(_ text: String?) -> String? {
        guard let text, parse(text) == nil else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(?:add|include)\s+(.+?)(?:\s+and\b.*)?$"#) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              match.numberOfRanges >= 2,
              let capture = Range(match.range(at: 1), in: trimmed)
        else { return nil }
        var value = sanitize(String(trimmed[capture]))
        if let insteadRange = value.range(of: " instead", options: [.caseInsensitive, .backwards]),
           insteadRange.upperBound == value.endIndex {
            value = String(value[..<insteadRange.lowerBound])
        }
        if let regex = try? NSRegularExpression(pattern: #"(?i)^\d+\s+sets?\s+of\s+"#),
           let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
           let junk = Range(match.range, in: value),
           junk.lowerBound == value.startIndex {
            value = String(value[junk.upperBound...])
        }
        return value.count >= 3 ? value : nil
    }

    static func parseMove(_ text: String?) -> Move? {
        guard let text else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Word boundaries so `place` inside `replace` cannot eat the swap clause.
        let pattern = #"(?i)\b(?:move|put|place)\b\s+(?:(it|that|them|this)|(.+?))?\s*(?:(?:to|at)\s+(?:the\s+)?)?(start|front|first|beginning|end|last)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              match.numberOfRanges >= 4,
              let posRange = Range(match.range(at: 3), in: trimmed)
        else { return nil }

        let posRaw = String(trimmed[posRange]).lowercased()
        let position: Move.Position = ["end", "last"].contains(posRaw) ? .end : .start

        if match.range(at: 1).location != NSNotFound {
            return Move(target: nil, position: position)
        }
        if match.range(at: 2).location != NSNotFound,
           let namedRange = Range(match.range(at: 2), in: trimmed) {
            let named = sanitize(String(trimmed[namedRange]))
            if named.count >= 3 {
                return Move(target: named, position: position)
            }
        }
        return Move(target: nil, position: position)
    }

    static func expandOrder(
        sessionOrder: [String],
        replacing fromID: String?,
        with toID: String?,
        moving targetID: String,
        to position: Move.Position
    ) -> [String] {
        var order = sessionOrder
        if let fromID, let toID, fromID != toID,
           let index = order.firstIndex(of: fromID) {
            order[index] = toID
        } else if let toID, !order.contains(toID) {
            order.append(toID)
        }
        guard let current = order.firstIndex(of: targetID) else { return order }
        order.remove(at: current)
        switch position {
        case .start:
            order.insert(targetID, at: 0)
        case .end:
            order.append(targetID)
        }
        return order
    }

    static func isPronoun(_ value: String) -> Bool {
        ["it", "that", "this", "them"].contains(value.lowercased())
    }

    private static func sanitize(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.count >= 2, value.first == value.last, ["\"", "'", "“", "”"].contains(value.first) {
            value = String(value.dropFirst().dropLast())
            value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let prefixes = [
            "can we do ", "can i do ", "let's do ", "lets do ", "i want ",
            "please ", "try ", "use ", "do ",
            "the ", "a ", "an ", "my ", "some ", "out ",
        ]
        var stripped = true
        while stripped {
            stripped = false
            let lower = value.lowercased()
            for prefix in prefixes {
                if lower.hasPrefix(prefix) {
                    value = String(value.dropFirst(prefix.count))
                    stripped = true
                    break
                }
            }
        }
        for suffix in [" and start", " please", " now", " thanks"] {
            if value.lowercased().hasSuffix(suffix) {
                value = String(value.dropLast(suffix.count))
            }
        }
        while let last = value.last, ".,!?\"'“”".contains(last) {
            value.removeLast()
        }
        while let first = value.first, "\"'“”".contains(first) {
            value.removeFirst()
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
