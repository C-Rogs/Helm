import Foundation

/// Wrist / Live Activity set line: `Set 2/4 . 80 KG . rpe 8`.
/// Descriptors stay sentence/lower case; numeric tokens are the values.
public struct WatchCompanionSetLineToken: Equatable, Sendable {
    public let text: String
    public let isValue: Bool

    public init(text: String, isValue: Bool) {
        self.text = text
        self.isValue = isValue
    }
}

public enum WatchCompanionSetLine {
    public static func make(setNumber: Int?, setCount: Int?, targetSummary: String?) -> String {
        tokens(setNumber: setNumber, setCount: setCount, targetSummary: targetSummary)
            .map(\.text)
            .joined()
    }

    public static func tokens(
        setNumber: Int?,
        setCount: Int?,
        targetSummary: String?
    ) -> [WatchCompanionSetLineToken] {
        var result: [WatchCompanionSetLineToken] = []

        func appendSeparator() {
            guard !result.isEmpty else { return }
            result.append(WatchCompanionSetLineToken(text: " . ", isValue: false))
        }

        if let setNumber, let setCount {
            result.append(WatchCompanionSetLineToken(text: "Set ", isValue: false))
            result.append(WatchCompanionSetLineToken(text: "\(setNumber)/\(setCount)", isValue: true))
        }
        if let kilograms = kilograms(from: targetSummary) {
            appendSeparator()
            result.append(WatchCompanionSetLineToken(text: kilograms, isValue: true))
            result.append(WatchCompanionSetLineToken(text: " KG", isValue: false))
        }
        if let rpe = rpe(from: targetSummary) {
            appendSeparator()
            result.append(WatchCompanionSetLineToken(text: "rpe ", isValue: false))
            result.append(WatchCompanionSetLineToken(text: rpe, isValue: true))
        }
        return result
    }

    private static func kilograms(from summary: String?) -> String? {
        guard let summary, let match = firstMatch(#"(\d+(?:\.\d+)?)\s*kg"#, in: summary) else {
            return nil
        }
        return displayNumber(match)
    }

    private static func rpe(from summary: String?) -> String? {
        guard let summary, let match = firstMatch(#"RPE\s+(\d+(?:\.\d+)?)"#, in: summary) else {
            return nil
        }
        return displayNumber(match)
    }

    private static func displayNumber(_ raw: String) -> String {
        guard let value = Double(raw) else { return raw }
        if value.truncatingRemainder(dividingBy: 1) == 0 {
            return String(format: "%.0f", value)
        }
        return String(format: "%g", value)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range), match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text)
        else {
            return nil
        }
        return String(text[capture])
    }
}
