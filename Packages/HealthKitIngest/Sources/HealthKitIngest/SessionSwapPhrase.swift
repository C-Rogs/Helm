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
        parseAddList(text).first
    }

    /// "add dumbbell curls and leg extensions" → two lifts.
    /// "add face pull and move it to the start" → one lift (move is not a second add).
    /// "Add in crunch machine at 32kg" → "crunch machine" (weight suffix stripped).
    static func parseAddList(_ text: String?) -> [String] {
        guard let text, parse(text) == nil else { return [] }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let regex = try? NSRegularExpression(pattern: #"(?i)(?:add|include)\s+(.+)$"#) else {
            return []
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, range: range),
              match.numberOfRanges >= 2,
              let capture = Range(match.range(at: 1), in: trimmed)
        else { return [] }

        var rest = String(trimmed[capture])
        if let moveStrip = try? NSRegularExpression(
            pattern: #"(?i)\s+and\s+(?:then\s+)?(?:move|put|place)\b.*$"#
        ) {
            let restRange = NSRange(rest.startIndex..., in: rest)
            if let moveMatch = moveStrip.firstMatch(in: rest, range: restRange),
               let drop = Range(moveMatch.range, in: rest) {
                rest = String(rest[..<drop.lowerBound])
            }
        }

        let parts = rest
            .replacingOccurrences(
                of: #"(?i)\s*(?:,\s*and|and then|&|plus|,|and)\s+"#,
                with: "\u{1e}",
                options: .regularExpression
            )
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .map(String.init)

        var results: [String] = []
        var seen = Set<String>()
        for part in parts {
            var value = sanitize(part)
            value = stripLeadingAddNoise(value)
            value = stripTrailingLoadPhrase(value)
            if let insteadRange = value.range(of: " instead", options: [.caseInsensitive, .backwards]),
               insteadRange.upperBound == value.endIndex {
                value = String(value[..<insteadRange.lowerBound])
            }
            if let qty = try? NSRegularExpression(pattern: #"(?i)^\d+\s+sets?\s+of\s+"#),
               let qtyMatch = qty.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
               let junk = Range(qtyMatch.range, in: value),
               junk.lowerBound == value.startIndex {
                value = String(value[junk.upperBound...])
            }
            // "another exercise. Crunch machine" / "new exercise crunch machine"
            if let exerciseSplit = try? NSRegularExpression(
                pattern: #"(?i)^(?:another|a new|new)\s+exercises?\s*[.\-:,]?\s*"#
            ),
               let splitMatch = exerciseSplit.firstMatch(
                in: value,
                range: NSRange(value.startIndex..., in: value)
               ),
               let junk = Range(splitMatch.range, in: value),
               junk.lowerBound == value.startIndex {
                value = String(value[junk.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            let key = value.lowercased()
            guard value.count >= 3, seen.insert(key).inserted else { continue }
            // Bare "new exercise" / "another exercise" is intent-only, not a lift name.
            if key == "new exercise" || key == "another exercise" || key == "an exercise" {
                continue
            }
            results.append(value)
        }
        return results
    }

    /// Pulls an absolute kg from "… at 32kg" / "… @ 32 kg" when the athlete names a load with the add.
    static func parseNamedLoadKg(_ text: String?) -> Double? {
        guard let text else { return nil }
        let patterns = [
            #"(?i)(?:at|@)\s*(\d+(?:\.\d+)?)\s*kg\b"#,
            #"(?i)(?:at|@)\s*(\d+(?:\.\d+)?)\s*kilos?\b"#,
            #"(?i)\b(\d+(?:\.\d+)?)\s*kg\b"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  match.numberOfRanges >= 2,
                  let capture = Range(match.range(at: 1), in: text),
                  let value = Double(text[capture]),
                  value > 0
            else { continue }
            return value
        }
        return nil
    }

    private static func stripLeadingAddNoise(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefixes = ["in ", "on ", "the ", "a ", "an "]
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
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripTrailingLoadPhrase(_ raw: String) -> String {
        var value = raw
        let patterns = [
            #"(?i)\s+(?:at|@)\s*\d+(?:\.\d+)?\s*(?:kg|kilos?)?\s*$"#,
            #"(?i)\s+\d+(?:\.\d+)?\s*(?:kg|kilos?)\s*$"#,
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(value.startIndex..., in: value)
            if let match = regex.firstMatch(in: value, range: range),
               let drop = Range(match.range, in: value) {
                value = String(value[..<drop.lowerBound])
            }
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
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
            "please ", "try ", "use ", "do ", "and ",
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
