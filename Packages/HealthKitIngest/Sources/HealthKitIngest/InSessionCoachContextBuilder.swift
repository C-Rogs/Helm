import Core
import Foundation
import Persistence

/// Live vitals captured during an active Train session for in-session coach context.
public struct InSessionLiveVitals: Sendable, Equatable {
    public let currentHeartRateBPM: Int?
    public let averageHeartRateBPM: Int?
    public let sampleCount: Int
    public let sessionElapsedSeconds: Int?

    public init(
        currentHeartRateBPM: Int? = nil,
        averageHeartRateBPM: Int? = nil,
        sampleCount: Int = 0,
        sessionElapsedSeconds: Int? = nil
    ) {
        self.currentHeartRateBPM = currentHeartRateBPM
        self.averageHeartRateBPM = averageHeartRateBPM
        self.sampleCount = sampleCount
        self.sessionElapsedSeconds = sessionElapsedSeconds
    }

    public static func from(
        buffer: SessionHeartRateBuffer,
        currentBPM: Int?,
        sessionStartedAt: Date?,
        now: Date = Date()
    ) -> InSessionLiveVitals {
        let samples = buffer.samples
        let average: Int?
        if samples.isEmpty {
            average = nil
        } else {
            average = Int((Double(samples.map(\.bpm).reduce(0, +)) / Double(samples.count)).rounded())
        }
        let elapsed: Int?
        if let sessionStartedAt {
            elapsed = max(0, Int(now.timeIntervalSince(sessionStartedAt)))
        } else {
            elapsed = nil
        }
        return InSessionLiveVitals(
            currentHeartRateBPM: currentBPM ?? samples.last?.bpm,
            averageHeartRateBPM: average,
            sampleCount: samples.count,
            sessionElapsedSeconds: elapsed
        )
    }
}

/// Formats active-session state for in-session coach prompts.
public enum InSessionCoachContextBuilder {
    public static func sessionExerciseBlock(
        snapshot: ActiveSessionSnapshot,
        displayNames: [String: String],
        importContextNotes: [String] = []
    ) -> String {
        let sortedExercises = snapshot.session.exercises.sorted { $0.displayOrder < $1.displayOrder }
        var lines: [String] = []

        let completedSetCount = sortedExercises.reduce(0) { partial, exercise in
            partial + exercise.sets.filter { $0.status == .completed }.count
        }
        let plannedSetCount = sortedExercises.reduce(0) { partial, exercise in
            partial + exercise.sets.count
        }
        lines.append(
            "session_progress: \(completedSetCount)/\(plannedSetCount) sets completed, \(sortedExercises.count) exercises"
        )

        for (index, exercise) in sortedExercises.enumerated() {
            let label = ExerciseDisplayFormatter.friendlyName(
                for: exercise.exerciseID,
                displayNames: displayNames
            )
            let archetypeID = CoachArchetypeSupport.archetype(for: exercise.exerciseID)?.id ?? exercise.exerciseID
            lines.append("- slot \(index + 1) | \(archetypeID) | \(label)")

            let sortedSets = exercise.sets.sorted { $0.setIndex < $1.setIndex }
            for set in sortedSets {
                lines.append("  \(setLine(set))")
            }
        }

        if !importContextNotes.isEmpty {
            lines.append("")
            lines.append("Import context (non-exercise lines):")
            for note in importContextNotes {
                lines.append("- \(note)")
            }
        }

        return lines.joined(separator: "\n")
    }

    public static func availableExercisesBlock(_ picker: [ExerciseSummary]) -> String {
        let names = picker.map(\.displayName).filter { !$0.isEmpty }
        guard !names.isEmpty else { return "" }
        var lines: [String] = [
            "Available gym exercises (copy these exact names for add/swap targets):"
        ]
        lines.append(contentsOf: names.map { "- \($0)" })
        return lines.joined(separator: "\n")
    }

    public static func liveVitalsBlock(_ vitals: InSessionLiveVitals) -> String {
        var lines: [String] = ["# Live session"]
        if let elapsed = vitals.sessionElapsedSeconds {
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            lines.append("elapsed=\(minutes)m \(seconds)s")
        }
        if let current = vitals.currentHeartRateBPM {
            lines.append("current_hr_bpm=\(current)")
        } else {
            lines.append("current_hr_bpm=unavailable")
        }
        if let average = vitals.averageHeartRateBPM, vitals.sampleCount > 0 {
            lines.append("session_avg_hr_bpm=\(average) samples=\(vitals.sampleCount)")
        }
        return lines.joined(separator: "\n")
    }

    public static func sessionMetaBlock(
        snapshot: ActiveSessionSnapshot,
        now: Date = Date()
    ) -> String {
        var lines: [String] = ["# Session meta"]
        let title = snapshot.session.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        lines.append("title=\(title?.isEmpty == false ? title! : "untitled")")
        lines.append("status=\(snapshot.session.status.rawValue)")
        lines.append("source=\(snapshot.session.source.rawValue)")
        lines.append("recovery_state=\(snapshot.recoveryState.rawValue)")
        if let timer = snapshot.restTimer {
            lines.append("rest_timer_phase=\(timer.phase.rawValue)")
            if let remaining = timer.remainingSeconds(at: now) {
                lines.append("rest_remaining_s=\(remaining)")
            }
        } else {
            lines.append("rest_timer_phase=none")
        }
        return lines.joined(separator: "\n")
    }

    public static func importContextNotes(from notes: String?) -> [String] {
        guard let notes else { return [] }
        return notes
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func setLine(_ set: SetEntryDraft) -> String {
        let status = set.status == .completed ? "completed" : set.status.rawValue
        var parts: [String] = ["set \(set.setIndex + 1) (\(status)):"]

        if set.setType != .normal {
            parts.append(set.setType.rawValue)
        }
        if let mass = set.mass {
            parts.append(formatMass(mass.kilograms))
        }
        if let reps = set.reps {
            parts.append("x \(reps)")
        }
        if let duration = set.durationSeconds, duration > 0 {
            parts.append("\(duration)s")
        }
        if let distance = set.distanceKilometers, distance > 0 {
            parts.append(String(format: "%.2f km", distance))
        }
        if let rpe = set.rpe {
            parts.append("@ RPE \(formatNumber(rpe))")
        }
        if let rir = set.rir {
            parts.append("RIR \(formatNumber(rir))")
        }

        if parts.count == 1 {
            parts.append("n/a")
        }

        return parts.joined(separator: " ")
    }

    private static func formatMass(_ kilograms: Double) -> String {
        kilograms.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f kg", kilograms)
            : String(format: "%.1f kg", kilograms)
    }

    private static func formatNumber(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", value)
            : String(format: "%.1f", value)
    }
}
