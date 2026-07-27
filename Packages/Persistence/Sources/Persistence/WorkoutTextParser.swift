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

/// Parses pasted Hevy-style day text and planner checklist prescriptions into structured exercises and sets.
public enum WorkoutTextParser {
    private static let lbToKg = 0.453_592_37
    private static let nearFailureDefaultReps = 12

    private static let prescriptionExerciseHeaderPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^\[\s*\]\s*(.+)$"#)
    }()

    private static let prescriptionBulletPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"^[•\-\*]\s*(.+)$"#)
    }()

    private static let prescriptionSetsPattern: NSRegularExpression = {
        let pattern = #"(?i)^sets?:\s*(\d+)\s*x\s*(.+)$"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let prescriptionTargetWeightPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?i)^target\s+weight:\s*(.+)$"#)
    }()

    private static let prescriptionIntensityPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?i)^intensity:\s*(.+)$"#)
    }()

    private static let prescriptionRestPattern: NSRegularExpression = {
        try! NSRegularExpression(pattern: #"(?i)^rest:\s*(.+)$"#)
    }()

    private static let weightRangePattern: NSRegularExpression = {
        let pattern = #"([\d.]+)\s*(kg|lb)\s*[–\-]\s*([\d.]+)\s*(kg|lb)?"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static let singleWeightPattern: NSRegularExpression = {
        let pattern = #"([\d.]+)\s*(kg|lb)"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static let repRangePattern: NSRegularExpression = {
        let pattern = #"(\d+)\s*[–\-]\s*(\d+)"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let rpeRangePattern: NSRegularExpression = {
        let pattern = #"(?i)rpe\s+([\d.]+)\s*[–\-]\s*([\d.]+)"#
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let singleRPEPattern: NSRegularExpression = {
        let pattern = #"(?i)rpe\s+([\d.]+)"#
        return try! NSRegularExpression(pattern: pattern)
    }()

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

        let lineContents = nonBlankLines.map(\.content)
        if isPrescriptionFormat(lineContents),
           let prescription = parsePrescription(lines: lineContents) {
            return prescription
        }

        return parseHevyStyle(nonBlankLines: nonBlankLines)
    }

    private static func parseHevyStyle(nonBlankLines: [(index: Int, content: String)]) -> ParsedWorkout {
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

    // MARK: - Prescription / checklist format

    private static func isPrescriptionFormat(_ lines: [String]) -> Bool {
        var signals = 0
        for line in lines {
            if prescriptionExerciseTitle(from: line) != nil { signals += 1 }
            if prescriptionBulletBody(from: line) != nil { signals += 1 }
        }
        return signals >= 2
    }

    private static func parsePrescription(lines: [String]) -> ParsedWorkout? {
        var skippedLines: [String] = []
        var title: String?
        var exercises: [ParsedWorkoutExercise] = []
        var lineIndex = 0

        if let first = lines.first {
            title = stripLeadingEmoji(from: first)
            lineIndex = 1
        }

        while lineIndex < lines.count {
            let line = lines[lineIndex]

            if isPrescriptionPreamble(line) {
                skippedLines.append(line)
                lineIndex += 1
                continue
            }

            guard let exerciseTitle = prescriptionExerciseTitle(from: line) else {
                if prescriptionBulletBody(from: line) != nil {
                    skippedLines.append(line)
                }
                lineIndex += 1
                continue
            }

            lineIndex += 1
            var targetWeightText: String?
            var setsText: String?
            var intensityText: String?
            var restText: String?

            while lineIndex < lines.count {
                let nextLine = lines[lineIndex]
                if prescriptionExerciseTitle(from: nextLine) != nil { break }
                if isPrescriptionPreamble(nextLine) {
                    skippedLines.append(nextLine)
                    lineIndex += 1
                    continue
                }

                guard let bulletBody = prescriptionBulletBody(from: nextLine) else {
                    lineIndex += 1
                    continue
                }

                let bodyRange = NSRange(bulletBody.startIndex..<bulletBody.endIndex, in: bulletBody)
                if prescriptionTargetWeightPattern.firstMatch(in: bulletBody, range: bodyRange) != nil {
                    targetWeightText = bulletBody
                } else if prescriptionSetsPattern.firstMatch(in: bulletBody, range: bodyRange) != nil {
                    setsText = bulletBody
                } else if prescriptionIntensityPattern.firstMatch(in: bulletBody, range: bodyRange) != nil {
                    intensityText = bulletBody
                } else if prescriptionRestPattern.firstMatch(in: bulletBody, range: bodyRange) != nil {
                    restText = bulletBody
                } else {
                    skippedLines.append(nextLine)
                }
                lineIndex += 1
            }

            guard let setsText,
                  let parsedSets = parsePrescriptionSetsLine(setsText)
            else {
                skippedLines.append("[ ] \(exerciseTitle)")
                continue
            }

            let weight = targetWeightText.flatMap(parsePrescriptionWeight)
            let intensity = intensityText.flatMap(parsePrescriptionIntensity)
            let restSeconds = restText.flatMap(parsePrescriptionRestLine)

            var prescriptionNotes: [String] = []
            if let weightNote = weight?.note { prescriptionNotes.append(weightNote) }
            if let setsNote = parsedSets.note { prescriptionNotes.append(setsNote) }
            if let intensityNote = intensity?.note { prescriptionNotes.append(intensityNote) }
            let combinedNote = prescriptionNotes.isEmpty ? nil : prescriptionNotes.joined(separator: "; ")

            let setType: SetType = weight?.isBodyweight == true ? .bodyweight : .normal
            let sets = (0..<parsedSets.count).map { offset in
                ParsedWorkoutSet(
                    setIndex: offset + 1,
                    setType: setType,
                    mass: weight?.mass,
                    reps: parsedSets.reps,
                    rpe: intensity?.rpe,
                    prescriptionNote: combinedNote
                )
            }

            guard !sets.isEmpty else { continue }
            exercises.append(
                ParsedWorkoutExercise(
                    exerciseTitle: exerciseTitle,
                    sets: sets,
                    restDurationSeconds: restSeconds
                )
            )
        }

        guard !exercises.isEmpty else { return nil }
        return ParsedWorkout(
            title: title ?? "Workout",
            exercises: exercises,
            skippedLines: skippedLines
        )
    }

    private static func prescriptionExerciseTitle(from line: String) -> String? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = prescriptionExerciseHeaderPattern.firstMatch(in: line, range: range),
              let title = stringCapture(1, in: line, match: match)
        else { return nil }
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func prescriptionBulletBody(from line: String) -> String? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = prescriptionBulletPattern.firstMatch(in: line, range: range),
              let body = stringCapture(1, in: line, match: match)
        else { return nil }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isPrescriptionPreamble(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.hasPrefix("bodyweight baseline:") { return true }
        if lower.hasPrefix("warm-up:") || lower.hasPrefix("warmup:") { return true }
        return false
    }

    private static func stripLeadingEmoji(from text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = result.unicodeScalars.first,
              !first.isASCII || !CharacterSet.alphanumerics.contains(first) {
            result = String(result.dropFirst()).trimmingCharacters(in: .whitespacesAndNewlines)
            if result.isEmpty { break }
        }
        return result.isEmpty ? text.trimmingCharacters(in: .whitespacesAndNewlines) : result
    }

    private static func parsePrescriptionSetsLine(_ line: String) -> (count: Int, reps: Int, note: String?)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = prescriptionSetsPattern.firstMatch(in: line, range: range),
              let count = intCapture(1, in: line, match: match),
              let repsPart = stringCapture(2, in: line, match: match),
              count > 0
        else { return nil }

        let normalizedReps = repsPart.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = normalizedReps.lowercased()
        var note: String?

        if lower.contains("near-failure") || lower.contains("near failure") {
            if normalizedReps.contains("(") || normalizedReps.contains("+") {
                note = normalizedReps
            } else {
                note = "to near-failure"
            }
            return (count, nearFailureDefaultReps, note)
        }

        if normalizedReps.contains("(") || normalizedReps.contains("+") {
            if let parenStart = normalizedReps.firstIndex(of: "(") {
                note = String(normalizedReps[parenStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            } else if let plusRange = normalizedReps.range(of: #"(\+"#, options: .regularExpression) {
                note = String(normalizedReps[plusRange.lowerBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        let repsToken = normalizedReps
            .replacingOccurrences(of: #"(?i)\breps?\b"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let reps = parseMidpointInt(from: repsToken) ?? Int(repsToken) {
            return (count, reps, note)
        }
        return nil
    }

    private static func parsePrescriptionWeight(_ line: String) -> (mass: Mass?, isBodyweight: Bool, note: String?)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = prescriptionTargetWeightPattern.firstMatch(in: line, range: range),
              let body = stringCapture(1, in: line, match: match)
        else { return nil }

        let lower = body.lowercased()
        if lower.contains("bodyweight") {
            var note = body
            if let bracketStart = body.firstIndex(of: "[") {
                note = String(body[bracketStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return (nil, true, note.isEmpty ? "Bodyweight" : note)
        }

        var noteParts: [String] = []
        if lower.contains("per db") || lower.contains("per dumbbell") {
            noteParts.append("per DB")
        }
        if let bracketStart = body.firstIndex(of: "[") {
            noteParts.append(String(body[bracketStart...]).trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let weightPart = body.split(separator: "[").first.map(String.init) ?? body
        guard let kilograms = parseMidpointWeight(from: weightPart) else { return nil }
        let note = noteParts.isEmpty ? nil : noteParts.joined(separator: "; ")
        return (Mass(kilograms: kilograms), false, note)
    }

    private static func parsePrescriptionIntensity(_ line: String) -> (rpe: Double?, note: String?)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = prescriptionIntensityPattern.firstMatch(in: line, range: range),
              let body = stringCapture(1, in: line, match: match)
        else { return nil }

        let bodyRange = NSRange(body.startIndex..<body.endIndex, in: body)
        var rpe: Double?

        if let rpeMatch = rpeRangePattern.firstMatch(in: body, range: bodyRange),
           let low = doubleCapture(1, in: body, match: rpeMatch),
           let high = doubleCapture(2, in: body, match: rpeMatch) {
            rpe = (low + high) / 2
        } else if let rpeMatch = singleRPEPattern.firstMatch(in: body, range: bodyRange),
                  let value = doubleCapture(1, in: body, match: rpeMatch) {
            rpe = value
        }

        var note: String?
        if let parenStart = body.firstIndex(of: "("), let parenEnd = body.lastIndex(of: ")"), parenStart < parenEnd {
            note = String(body[body.index(after: parenStart)..<parenEnd]).trimmingCharacters(in: .whitespacesAndNewlines)
        }

        return (rpe, note)
    }

    private static func parsePrescriptionRestLine(_ line: String) -> Int? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = prescriptionRestPattern.firstMatch(in: line, range: range),
              let body = stringCapture(1, in: line, match: match)
        else { return nil }
        return parseRestLine(body)
    }

    private static func parseMidpointWeight(from text: String) -> Double? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = weightRangePattern.firstMatch(in: text, range: range),
           let low = doubleCapture(1, in: text, match: match),
           let high = doubleCapture(3, in: text, match: match) {
            let lowUnit = stringCapture(2, in: text, match: match)?.lowercased() ?? "kg"
            let highUnit = stringCapture(4, in: text, match: match)?.lowercased() ?? lowUnit
            let lowKg = lowUnit == "lb" ? low * lbToKg : low
            let highKg = highUnit == "lb" ? high * lbToKg : high
            return (lowKg + highKg) / 2
        }

        if let match = singleWeightPattern.firstMatch(in: text, range: range),
           let value = doubleCapture(1, in: text, match: match),
           let unit = stringCapture(2, in: text, match: match)?.lowercased() {
            return unit == "lb" ? value * lbToKg : value
        }
        return nil
    }

    private static func parseMidpointInt(from text: String) -> Int? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        if let match = repRangePattern.firstMatch(in: text, range: range),
           let low = intCapture(1, in: text, match: match),
           let high = intCapture(2, in: text, match: match) {
            return (low + high) / 2
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
