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
    public static func targetSummary(
        massKilograms: Double?,
        rpe: Double?,
        durationSeconds: Int? = nil,
        distanceKilometers: Double? = nil,
        fallback: String?
    ) -> String? {
        let resolvedDuration = durationSeconds.flatMap { $0 > 0 ? durationLabel(seconds: $0) : nil }
            ?? duration(from: fallback).map { "\($0) min" }
        let resolvedDistance = distanceKilometers.flatMap { value in
            value.isFinite && value > 0 ? "\(displayNumber(value)) km" : nil
        } ?? kilometers(from: fallback).map { "\($0) km" }
        let resolvedMass = massKilograms.flatMap { value in
            value.isFinite && value > 0 ? displayNumber(value) : nil
        } ?? kilograms(from: fallback)
        let resolvedRPE = rpe.flatMap { value in
            value.isFinite && value > 0 ? displayNumber(value) : nil
        } ?? Self.rpe(from: fallback)

        let parts = [
            resolvedDuration,
            resolvedDistance,
            resolvedMass.map { "\($0)kg" },
            resolvedRPE.map { "RPE \($0)" },
        ].compactMap { $0 }
        return parts.isEmpty ? fallback : parts.joined(separator: " · ")
    }

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
        if let duration = duration(from: targetSummary) {
            appendSeparator()
            result.append(WatchCompanionSetLineToken(text: duration, isValue: true))
            result.append(WatchCompanionSetLineToken(text: " MIN", isValue: false))
        }
        if let kilometers = kilometers(from: targetSummary) {
            appendSeparator()
            result.append(WatchCompanionSetLineToken(text: kilometers, isValue: true))
            result.append(WatchCompanionSetLineToken(text: " KM", isValue: false))
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

    private static func duration(from summary: String?) -> String? {
        guard let summary, let match = firstMatch(#"(\d+(?:\.\d+)?)\s*min"#, in: summary) else {
            return nil
        }
        return displayNumber(match)
    }

    private static func kilometers(from summary: String?) -> String? {
        guard let summary, let match = firstMatch(#"(\d+(?:\.\d+)?)\s*km"#, in: summary) else {
            return nil
        }
        return displayNumber(match)
    }

    private static func durationLabel(seconds: Int) -> String {
        let minutes = Double(seconds) / 60
        return "\(displayNumber(minutes)) min"
    }

    private static func displayNumber(_ raw: String) -> String {
        guard let value = Double(raw) else { return raw }
        return displayNumber(value)
    }

    private static func displayNumber(_ value: Double) -> String {
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
