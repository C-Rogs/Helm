import CoachLLM
import Core
import Foundation
import Persistence

/// Single persist implementation for Memory profile mutations.
public enum HelmMemoryApplier: Sendable {
    public static func apply(
        _ write: HelmMemoryWrite,
        persistence: PersistenceStore
    ) throws {
        switch write {
        case let .fromCoachPayload(payload, today):
            try applyCoachPayload(payload, persistence: persistence, today: today)
        case let .replaceProfile(profile):
            try persistence.memoryProfile.save(profile)
        case let .applyRefinements(entries, today):
            try applyRefinements(entries, persistence: persistence, today: today)
        case let .appendTrainingResponse(note, today):
            try appendTrainingResponse(note, persistence: persistence, today: today)
        }
    }

    public static func applyCoachPayload(
        _ payload: MemoryAdjustmentPayload,
        persistence: PersistenceStore,
        today: HelmDay
    ) throws {
        var profile = try persistence.memoryProfile.load()
        switch payload.action {
        case .add:
            let note = payload.standingConstraintNote?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !note.isEmpty else { return }
            let until = payload.untilDate.flatMap(HelmDay.init(formatted:))
            profile.standingConstraints = StandingConstraintNotes.append(
                note: note,
                joint: payload.joint,
                notedOn: today,
                until: until,
                to: profile.standingConstraints
            )
        case .clear:
            profile.standingConstraints = StandingConstraintNotes.clear(
                joint: payload.joint,
                on: today,
                in: profile.standingConstraints
            )
        }
        try persistence.memoryProfile.save(profile)
    }

    private static func applyRefinements(
        _ entries: [MemoryRefinementEntry],
        persistence: PersistenceStore,
        today: HelmDay
    ) throws {
        var profile = try persistence.memoryProfile.load()
        for entry in entries {
            applyRefinement(entry, to: &profile, today: today)
        }
        try persistence.memoryProfile.save(profile)
    }

    private static func applyRefinement(
        _ entry: MemoryRefinementEntry,
        to profile: inout MemoryProfile,
        today: HelmDay
    ) {
        let field = entry.field
        guard isStringField(field) else { return }

        if field == "standingConstraints" {
            switch entry.action {
            case .add, .merge:
                let note = entry.proposedValue.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !note.isEmpty else { return }
                profile.standingConstraints = StandingConstraintNotes.append(
                    note: note,
                    joint: nil,
                    notedOn: today,
                    until: nil,
                    to: profile.standingConstraints
                )
                return
            case .replace:
                setValue(of: field, in: &profile, to: entry.proposedValue)
                return
            case .remove:
                setValue(of: field, in: &profile, to: "")
                return
            }
        }

        switch entry.action {
        case .add, .merge:
            let current = currentValue(of: field, in: profile)
            let separator = current.isEmpty ? "" : "\n"
            setValue(of: field, in: &profile, to: current + separator + entry.proposedValue)
        case .replace:
            setValue(of: field, in: &profile, to: entry.proposedValue)
        case .remove:
            setValue(of: field, in: &profile, to: "")
        }
    }

    private static func appendTrainingResponse(
        _ note: String,
        persistence: PersistenceStore,
        today: HelmDay
    ) throws {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var profile = try persistence.memoryProfile.load()
        let line = "\(today.formatted): \(trimmed)"
        if profile.trainingResponses.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile.trainingResponses = line
        } else {
            profile.trainingResponses += "\n" + line
        }
        try persistence.memoryProfile.save(profile)
    }

    private static func isStringField(_ field: String) -> Bool {
        switch field {
        case "baselinesSummary", "preferences", "standingConstraints",
             "whatHasWorked", "injuryHistory", "trainingResponses",
             "nutritionPatterns":
            true
        default:
            false
        }
    }

    private static func currentValue(of field: String, in profile: MemoryProfile) -> String {
        switch field {
        case "baselinesSummary": profile.baselinesSummary
        case "preferences": profile.preferences
        case "standingConstraints": profile.standingConstraints
        case "whatHasWorked": profile.whatHasWorked
        case "injuryHistory": profile.injuryHistory
        case "trainingResponses": profile.trainingResponses
        case "nutritionPatterns": profile.nutritionPatterns
        default: ""
        }
    }

    private static func setValue(of field: String, in profile: inout MemoryProfile, to value: String) {
        switch field {
        case "baselinesSummary": profile.baselinesSummary = value
        case "preferences": profile.preferences = value
        case "standingConstraints": profile.standingConstraints = value
        case "whatHasWorked": profile.whatHasWorked = value
        case "injuryHistory": profile.injuryHistory = value
        case "trainingResponses": profile.trainingResponses = value
        case "nutritionPatterns": profile.nutritionPatterns = value
        default: break
        }
    }
}
