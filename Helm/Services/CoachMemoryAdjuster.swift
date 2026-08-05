import CoachLLM
import Core
import Foundation
import Persistence

enum CoachMemoryAdjuster {
    private static let shoulderSeedDefaultsKey = "helm.memory.seededShoulderNiggle.v1"

    static func apply(
        _ payload: MemoryAdjustmentPayload,
        persistence: PersistenceStore,
        today: HelmDay = HelmDay.day(for: Date(), calendar: .current)
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

    /// One-shot seed for Cameron's current shoulder niggle (launch-time).
    static func seedShoulderNiggleIfNeeded(
        persistence: PersistenceStore,
        today: HelmDay = HelmDay.day(for: Date(), calendar: .current),
        defaults: UserDefaults = .standard
    ) throws {
        if defaults.bool(forKey: shoulderSeedDefaultsKey) { return }

        let profile = try persistence.memoryProfile.load()
        let signals = StandingConstraintNotes.evaluate(profile.standingConstraints, on: today)
        if signals.activeJoints.contains("shoulder") {
            defaults.set(true, forKey: shoulderSeedDefaultsKey)
            return
        }
        let hasShoulderHistory = profile.standingConstraints.lowercased().contains("[joint:shoulder]")
            || profile.standingConstraints.lowercased().contains("shoulder")
        if hasShoulderHistory {
            defaults.set(true, forKey: shoulderSeedDefaultsKey)
            return
        }

        try apply(
            MemoryAdjustmentPayload(
                reply: "Saved shoulder recovery note.",
                action: .add,
                standingConstraintNote: "Shoulder niggle - soft pause overhead pressing; warm up and stretch more.",
                untilDate: today.adding(days: StandingConstraintNotes.defaultWindowDays).formatted,
                joint: "shoulder"
            ),
            persistence: persistence,
            today: today
        )
        defaults.set(true, forKey: shoulderSeedDefaultsKey)
    }
}
