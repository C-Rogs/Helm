import Foundation

/// One filled pattern slot ready for set allocation.
struct SlotAllocationCandidate: Sendable, Hashable {
    let slot: PatternSlot
    let exercise: CatalogExercise
    let rationale: String
    let evidenceIDs: [String]
}

/// Role-aware session set budget split (v1.2).
enum SessionSetAllocator {
    struct Allocation: Sendable, Hashable {
        let candidate: SlotAllocationCandidate
        let sets: Int
    }

    static func roleBounds(
        role: PatternSlotRole,
        thinSession: Bool
    ) -> (min: Int, max: Int) {
        if thinSession {
            switch role {
            case .primary: (2, 4)
            case .secondary: (1, 3)
            case .isolation: (1, 2)
            }
        } else {
            switch role {
            case .primary: (3, 4)
            case .secondary: (2, 4)
            case .isolation: (2, 3)
            }
        }
    }

    /// Allocate working sets across filled slots respecting duration budget, role floors, and weekly remaining.
    static func allocate(
        candidates: [SlotAllocationCandidate],
        budget: SessionDurationBudget,
        thinSession: Bool,
        volumeMultiplier: Double,
        remainingByMuscle: [MuscleGroup: Double]
    ) -> [Allocation] {
        guard !candidates.isEmpty else { return [] }

        let sessionBudget = max(
            1,
            safeInt(from: (Double(budget.maxTotalSets) * volumeMultiplier).rounded(), fallback: 1)
        )
        var kept = candidates
        var setsByIndex = Array(repeating: 0, count: kept.count)

        func minimumTotal(for list: [SlotAllocationCandidate]) -> Int {
            list.reduce(0) { partial, candidate in
                partial + roleBounds(role: candidate.slot.role, thinSession: thinSession).min
            }
        }

        func muscleCanAffordFloors(for list: [SlotAllocationCandidate]) -> Bool {
            var needed: [MuscleGroup: Int] = [:]
            for candidate in list {
                let floor = roleBounds(role: candidate.slot.role, thinSession: thinSession).min
                needed[candidate.slot.primaryMuscle, default: 0] += floor
            }
            for (muscle, floor) in needed {
                let remaining = remainingByMuscle[muscle, default: Double(budget.maxSetsPerSlot * 4)]
                if remaining + 0.001 < Double(floor) {
                    return false
                }
            }
            return true
        }

        while kept.count > 1,
              minimumTotal(for: kept) > sessionBudget || !muscleCanAffordFloors(for: kept) {
            if let dropIndex = kept.lastIndex(where: { !$0.slot.required }) {
                kept.remove(at: dropIndex)
            } else {
                break
            }
        }

        var muscleRemaining = remainingByMuscle
        seedFloors(
            kept: kept,
            thinSession: thinSession,
            setsByIndex: &setsByIndex,
            muscleRemaining: &muscleRemaining
        )

        var used = setsByIndex.reduce(0, +)
        let priority = kept.indices.sorted { lhs, rhs in
            let lRole = kept[lhs].slot.role
            let rRole = kept[rhs].slot.role
            if lRole != rRole {
                return rolePriority(lRole) < rolePriority(rRole)
            }
            return kept[lhs].slot.index < kept[rhs].slot.index
        }

        for index in priority {
            let candidate = kept[index]
            let bounds = roleBounds(role: candidate.slot.role, thinSession: thinSession)
            let muscle = candidate.slot.primaryMuscle
            while setsByIndex[index] < bounds.max,
                  used < sessionBudget,
                  muscleRemaining[muscle, default: 0] >= 1 {
                setsByIndex[index] += 1
                used += 1
                muscleRemaining[muscle, default: 0] -= 1
            }
        }

        return emitAllocations(kept: kept, setsByIndex: setsByIndex, thinSession: thinSession)
    }

    /// Give every kept slot its role floor, bounded by what the muscle can still absorb.
    private static func seedFloors(
        kept: [SlotAllocationCandidate],
        thinSession: Bool,
        setsByIndex: inout [Int],
        muscleRemaining: inout [MuscleGroup: Double]
    ) {
        for index in kept.indices {
            let candidate = kept[index]
            let bounds = roleBounds(role: candidate.slot.role, thinSession: thinSession)
            let muscle = candidate.slot.primaryMuscle
            let remaining = muscleRemaining[muscle, default: Double(bounds.max)]
            let affordable = safeInt(from: floor(remaining), fallback: 0)
            // A muscle with no headroom left earns no sets; the slot is dropped later
            // rather than forced up to its role floor.
            let assigned = remaining <= 0 ? 0 : min(bounds.max, max(bounds.min, affordable))
            setsByIndex[index] = assigned
            muscleRemaining[muscle] = max(0, muscleRemaining[muscle, default: 0] - Double(assigned))
        }
    }

    private static func emitAllocations(
        kept: [SlotAllocationCandidate],
        setsByIndex: [Int],
        thinSession: Bool
    ) -> [Allocation] {
        var allocations: [Allocation] = []
        for index in kept.indices {
            var sets = setsByIndex[index]
            if sets == 0 { continue }
            if !thinSession, sets < 2, !kept[index].slot.required { continue }
            if !thinSession, sets < 2 {
                sets = roleBounds(role: kept[index].slot.role, thinSession: thinSession).min
            }
            allocations.append(Allocation(candidate: kept[index], sets: PrescriptionBounds.clampSets(sets)))
        }
        return allocations
    }

    private static func rolePriority(_ role: PatternSlotRole) -> Int {
        switch role {
        case .primary: 0
        case .secondary: 1
        case .isolation: 2
        }
    }

    private static func safeInt(from value: Double, fallback: Int) -> Int {
        guard value.isFinite else { return fallback }
        guard value >= Double(Int.min), value <= Double(Int.max) else { return fallback }
        return Int(value)
    }
}
