import Core
import Foundation

public enum WorkoutTextParseError: Error, Sendable, Equatable {
    case emptyDocument
}

extension WorkoutTextParseError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyDocument:
            "The pasted text is empty."
        }
    }
}

/// Parses pasted Hevy-style day text into structured exercises and sets.
public enum WorkoutTextParser {
    private static let lbToKg = 0.453_592_37

    private static let setLinePattern: NSRegularExpression = {
        let pattern = #"(?i)^(?:set\s+(\d+)\s*:\s*)?([\d.]+)\s*(kg|lb)(?:\s+dbs?)?\s*[x×]\s*(\d+)(?:\s*@\s*([\d.]+)(?:\s*rpe)?)?(?:\s*\(([^)]+)\))?\s*$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let bodyweightSetPattern: NSRegularExpression = {
        let pattern = #"(?i)^(?:set\s+(\d+)\s*:\s*)?(?:x|×)\s*(\d+)(?:\s*@\s*([\d.]+)(?:\s*rpe)?)?(?:\s*\(([^)]+)\))?\s*$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let repsOnlyPattern: NSRegularExpression = {
        let pattern = #"(?i)^(?:set\s+(\d+)\s*:\s*)?(\d+)\s*reps?\s*(?:@\s*([\d.]+)(?:\s*rpe)?)?(?:\s*\(([^)]+)\))?\s*$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let restLinePattern: NSRegularExpression = {
        let pattern = #"(?i)^(?:\(?\s*)?(?:rest\s*:?\s*)?(\d+)\s*(s(?:ec(?:ond)?s?)?|m(?:in(?:ute)?s?)?)(?:\s*rest)?\s*\)?\s*$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let warmupParenPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?i)^warm[- ]?up$"#)
    }()

    private static let junkBeforeSetsPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?i)\bset\b"#)
    }()

    private static let compressedExercisePattern: NSRegularExpression = {
        let pattern = #"^(.+?):\s*(.+)$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    public static func parse(_ text: String) -> ParsedWorkout {
        let rawLines = text.components(separatedBy: .newlines)
        var nonBlankLines: [(index: Int, content: String)] = []
        for (offset, line) in rawLines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            nonBlankLines.append((offset, trimmed))
        }

        guard !nonBlankLines.isEmpty else {
            return ParsedWorkout(title: "Workout", exercises: [], skippedLines: [])
        }

        var skippedLines: [String] = []
        var title: String?
        var exercises: [ParsedWorkoutExercise] = []
        var currentExerciseTitle: String?
        var currentSets: [ParsedWorkoutSet] = []
        var pendingExerciseRest: Int?
        var lineIndex = 0

        func flushExerciseIfNeeded() {
            guard let currentExerciseTitle, !currentSets.isEmpty else { return }
            exercises.append(
                ParsedWorkoutExercise(
                    exerciseTitle: currentExerciseTitle,
                    sets: currentSets,
                    restDurationSeconds: pendingExerciseRest
                )
            )
            currentSets = []
            pendingExerciseRest = nil
        }

        if nonBlankLines.count >= 2,
           !isRecognizedSetLine(nonBlankLines[0].content),
           !isRestLine(nonBlankLines[0].content),
           !isCompressedExerciseLine(nonBlankLines[0].content),
           isRecognizedSetLine(nonBlankLines[1].content) {
            let orphanSetBeforeNextExercise = nonBlankLines.count >= 3
                && !isRecognizedSetLine(nonBlankLines[2].content)
                && !isRestLine(nonBlankLines[2].content)
                && !isCompressedExerciseLine(nonBlankLines[2].content)
            if orphanSetBeforeNextExercise {
                title = nonBlankLines[0].content
            } else {
                title = "Workout"
                currentExerciseTitle = nonBlankLines[0].content
            }
            lineIndex = 1
        } else {
            title = nonBlankLines[0].content
            lineIndex = 1
        }

        while lineIndex < nonBlankLines.count {
            let line = nonBlankLines[lineIndex].content
            let nextLine = lineIndex + 1 < nonBlankLines.count ? nonBlankLines[lineIndex + 1].content : nil

            if let parsedSet = parseSetLine(line, fallbackSetIndex: currentSets.count + 1) {
                guard currentExerciseTitle != nil else {
                    skippedLines.append(line)
                    lineIndex += 1
                    continue
                }
                currentSets.append(parsedSet)
            } else if let compressed = parseCompressedExerciseLine(line) {
                flushExerciseIfNeeded()
                exercises.append(compressed)
                currentExerciseTitle = nil
            } else if let restSeconds = parseRestLine(line) {
                guard currentExerciseTitle != nil else {
                    skippedLines.append(line)
                    lineIndex += 1
                    continue
                }
                if !currentSets.isEmpty, let nextLine, isRecognizedSetLine(nextLine) {
                    attachRest(restSeconds, toLastSetIn: &currentSets)
                } else {
                    pendingExerciseRest = restSeconds
                }
            } else if currentExerciseTitle != nil, currentSets.isEmpty {
                if looksLikeJunkBeforeFirstSet(line) {
                    skippedLines.append(line)
                } else {
                    currentExerciseTitle = line
                    pendingExerciseRest = nil
                }
            } else {
                flushExerciseIfNeeded()
                currentExerciseTitle = line
                pendingExerciseRest = nil
            }

            lineIndex += 1
        }

        flushExerciseIfNeeded()

        let resolvedTitle = title ?? "Workout"
        let resolvedExercises = exercises.filter { !$0.sets.isEmpty }

        return ParsedWorkout(
            title: resolvedTitle,
            exercises: resolvedExercises,
            skippedLines: skippedLines
        )
    }

    private static func attachRest(_ seconds: Int, toLastSetIn sets: inout [ParsedWorkoutSet]) {
        guard let last = sets.popLast() else { return }
        sets.append(
            ParsedWorkoutSet(
                id: last.id,
                setIndex: last.setIndex,
                setType: last.setType,
                mass: last.mass,
                reps: last.reps,
                rpe: last.rpe,
                prescriptionNote: last.prescriptionNote,
                restDurationSeconds: seconds
            )
        )
    }

    private static func looksLikeJunkBeforeFirstSet(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        return junkBeforeSetsPattern.firstMatch(in: line, range: range) != nil
    }

    private static func isRecognizedSetLine(_ line: String) -> Bool {
        parseSetLine(line, fallbackSetIndex: 1) != nil
    }

    private static func isRestLine(_ line: String) -> Bool {
        parseRestLine(line) != nil
    }

    private static func isCompressedExerciseLine(_ line: String) -> Bool {
        if isRecognizedSetLine(line) || isRestLine(line) { return false }
        return parseCompressedExerciseLine(line) != nil
    }

    private static func parseRestLine(_ line: String) -> Int? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = restLinePattern.firstMatch(in: line, range: range),
              let value = intCapture(1, in: line, match: match),
              let unit = stringCapture(2, in: line, match: match)?.lowercased()
        else { return nil }

        if unit.hasPrefix("m") {
            return value * 60
        }
        return value
    }

    private static func parseSetLine(_ line: String, fallbackSetIndex: Int) -> ParsedWorkoutSet? {
        if let weighted = parseWeightedSetLine(line, fallbackSetIndex: fallbackSetIndex) {
            return weighted
        }
        if let bodyweight = parseBodyweightSetLine(line, fallbackSetIndex: fallbackSetIndex) {
            return bodyweight
        }
        return parseRepsOnlySetLine(line, fallbackSetIndex: fallbackSetIndex)
    }

    private static func parseWeightedSetLine(_ line: String, fallbackSetIndex: Int) -> ParsedWorkoutSet? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = setLinePattern.firstMatch(in: line, range: range) else { return nil }

        let setIndex = intCapture(1, in: line, match: match) ?? fallbackSetIndex
        guard let weightValue = doubleCapture(2, in: line, match: match),
              let unit = stringCapture(3, in: line, match: match)?.lowercased(),
              let reps = intCapture(4, in: line, match: match)
        else { return nil }

        let kilograms: Double
        switch unit {
        case "kg":
            kilograms = weightValue
        case "lb":
            kilograms = weightValue * lbToKg
        default:
            return nil
        }

        return makeParsedSet(
            setIndex: setIndex,
            mass: Mass(kilograms: kilograms),
            reps: reps,
            rpe: doubleCapture(5, in: line, match: match),
            parenNote: stringCapture(6, in: line, match: match)
        )
    }

    private static func parseBodyweightSetLine(_ line: String, fallbackSetIndex: Int) -> ParsedWorkoutSet? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = bodyweightSetPattern.firstMatch(in: line, range: range) else { return nil }

        let setIndex = intCapture(1, in: line, match: match) ?? fallbackSetIndex
        guard let reps = intCapture(2, in: line, match: match) else { return nil }

        return makeParsedSet(
            setIndex: setIndex,
            mass: nil,
            reps: reps,
            rpe: doubleCapture(3, in: line, match: match),
            parenNote: stringCapture(4, in: line, match: match),
            defaultSetType: .bodyweight
        )
    }

    private static func parseRepsOnlySetLine(_ line: String, fallbackSetIndex: Int) -> ParsedWorkoutSet? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = repsOnlyPattern.firstMatch(in: line, range: range) else { return nil }

        let setIndex = intCapture(1, in: line, match: match) ?? fallbackSetIndex
        guard let reps = intCapture(2, in: line, match: match) else { return nil }

        return makeParsedSet(
            setIndex: setIndex,
            mass: nil,
            reps: reps,
            rpe: doubleCapture(3, in: line, match: match),
            parenNote: stringCapture(4, in: line, match: match),
            defaultSetType: .bodyweight
        )
    }

    private static func makeParsedSet(
        setIndex: Int,
        mass: Mass?,
        reps: Int,
        rpe: Double?,
        parenNote: String?,
        defaultSetType: SetType = .normal
    ) -> ParsedWorkoutSet {
        var setType = defaultSetType
        var prescriptionNote: String?

        if let parenNote, !parenNote.isEmpty {
            let parenRange = NSRange(parenNote.startIndex..<parenNote.endIndex, in: parenNote)
            if warmupParenPattern.firstMatch(in: parenNote, range: parenRange) != nil {
                setType = .warmup
            } else {
                prescriptionNote = parenNote
            }
        }

        return ParsedWorkoutSet(
            setIndex: setIndex,
            setType: setType,
            mass: mass,
            reps: reps,
            rpe: rpe,
            prescriptionNote: prescriptionNote
        )
    }

    /// Handles summarizer-style compressed lines, e.g. `Bench Press (Barbell): 3 x 8 @ 80kg`.
    private static func parseCompressedExerciseLine(_ line: String) -> ParsedWorkoutExercise? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = compressedExercisePattern.firstMatch(in: line, range: range),
              match.numberOfRanges == 3,
              let titleRange = Range(match.range(at: 1), in: line),
              let bodyRange = Range(match.range(at: 2), in: line)
        else { return nil }

        let title = String(line[titleRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        let body = String(line[bodyRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, !body.isEmpty else { return nil }
        if title.range(of: #"^set\s+\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }

        let segments = body.split(separator: ";", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !segments.isEmpty else { return nil }

        var sets: [ParsedWorkoutSet] = []
        var setIndex = 1

        for segment in segments {
            let lower = segment.lowercased()
            let isWarmup = lower.hasPrefix("warmup ")
            let workingSegment = isWarmup ? String(segment.dropFirst("warmup ".count)) : segment

            if let block = parseCompressedWorkingSegment(workingSegment, startingSetIndex: setIndex, isWarmup: isWarmup) {
                sets.append(contentsOf: block.sets)
                setIndex = block.nextSetIndex
                continue
            }

            if let single = parseSetLine(workingSegment, fallbackSetIndex: setIndex) {
                sets.append(
                    ParsedWorkoutSet(
                        id: single.id,
                        setIndex: setIndex,
                        setType: isWarmup ? .warmup : single.setType,
                        mass: single.mass,
                        reps: single.reps,
                        rpe: single.rpe,
                        prescriptionNote: single.prescriptionNote,
                        restDurationSeconds: single.restDurationSeconds
                    )
                )
                setIndex += 1
                continue
            }

            return nil
        }

        guard !sets.isEmpty else { return nil }
        return ParsedWorkoutExercise(exerciseTitle: title, sets: sets)
    }

    private static func parseCompressedWorkingSegment(
        _ segment: String,
        startingSetIndex: Int,
        isWarmup: Bool
    ) -> (sets: [ParsedWorkoutSet], nextSetIndex: Int)? {
        let normalized = segment
            .replacingOccurrences(of: "×", with: "x")
            .replacingOccurrences(of: "\u{2014}", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let countRepsWeight = #"^(\d+)\s*x\s*(\d+)\s*@\s*([\d.]+)\s*(kg|lb)?"#
        if let regex = try? NSRegularExpression(pattern: countRepsWeight, options: [.caseInsensitive]),
           let match = regex.firstMatch(
               in: normalized,
               range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
           ),
           let count = intCapture(1, in: normalized, match: match),
           let reps = intCapture(2, in: normalized, match: match),
           let weightValue = doubleCapture(3, in: normalized, match: match),
           count > 0 {
            let unit = stringCapture(4, in: normalized, match: match)?.lowercased() ?? "kg"
            let kilograms = unit == "lb" ? weightValue * lbToKg : weightValue
            let sets = (0..<count).map { offset in
                ParsedWorkoutSet(
                    setIndex: startingSetIndex + offset,
                    setType: isWarmup ? .warmup : .normal,
                    mass: Mass(kilograms: kilograms),
                    reps: reps
                )
            }
            return (sets, startingSetIndex + count)
        }

        let weightRepsList = #"^([\d.]+)\s*(kg|lb)\s*x\s*(.+)$"#
        if let regex = try? NSRegularExpression(pattern: weightRepsList, options: [.caseInsensitive]),
           let match = regex.firstMatch(
               in: normalized,
               range: NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
           ),
           let weightValue = doubleCapture(1, in: normalized, match: match),
           let unit = stringCapture(2, in: normalized, match: match)?.lowercased(),
           let repsPart = stringCapture(3, in: normalized, match: match) {
            let kilograms = unit == "lb" ? weightValue * lbToKg : weightValue
            let repsValues = repsPart.split(separator: "/").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
            guard !repsValues.isEmpty else { return nil }
            let sets = repsValues.enumerated().map { offset, reps in
                ParsedWorkoutSet(
                    setIndex: startingSetIndex + offset,
                    setType: isWarmup ? .warmup : .normal,
                    mass: Mass(kilograms: kilograms),
                    reps: reps
                )
            }
            return (sets, startingSetIndex + repsValues.count)
        }

        return nil
    }

    private static func stringCapture(_ group: Int, in line: String, match: NSTextCheckingResult) -> String? {
        guard match.range(at: group).location != NSNotFound,
              let range = Range(match.range(at: group), in: line)
        else { return nil }
        return String(line[range])
    }

    private static func intCapture(_ group: Int, in line: String, match: NSTextCheckingResult) -> Int? {
        guard let text = stringCapture(group, in: line, match: match) else { return nil }
        return Int(text)
    }

    private static func doubleCapture(_ group: Int, in line: String, match: NSTextCheckingResult) -> Double? {
        guard let text = stringCapture(group, in: line, match: match) else { return nil }
        return Double(text)
    }
}
