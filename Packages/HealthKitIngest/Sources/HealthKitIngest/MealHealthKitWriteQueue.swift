import Foundation

/// Serializes HealthKit meal writes per `mealID` so a background save cannot land
/// after a later edit or delete of the same meal.
public final class MealHealthKitWriteQueue: Sendable {
    private let gate = Gate()

    public init() {}

    /// Registers `operation` to run after any in-flight work for `mealID`.
    /// Returns once the task is queued, not when HealthKit finishes.
    public func enqueue(mealID: String, operation: @escaping @Sendable () async -> Void) async {
        await gate.enqueue(mealID: Self.key(mealID), operation: operation)
    }

    public func wait(for mealID: String) async {
        await gate.wait(for: Self.key(mealID))
    }

    public func waitAll() async {
        await gate.waitAll()
    }

    private static func key(_ mealID: String) -> String {
        mealID.lowercased()
    }

    private actor Gate {
        private var tasks: [String: Task<Void, Never>] = [:]
        private var generation: [String: UInt64] = [:]
        private var inflight = 0

        func enqueue(mealID: String, operation: @escaping @Sendable () async -> Void) {
            generation[mealID, default: 0] += 1
            inflight += 1
            let previous = tasks[mealID]
            let task = Task {
                await previous?.value
                await operation()
                await self.noteFinished()
            }
            tasks[mealID] = task
        }

        func wait(for mealID: String) async {
            let target = generation[mealID] ?? 0
            while (generation[mealID] ?? 0) >= target {
                guard let task = tasks[mealID] else { return }
                let genAtWait = generation[mealID] ?? 0
                await task.value
                if (generation[mealID] ?? 0) == genAtWait {
                    tasks[mealID] = nil
                    return
                }
            }
        }

        func waitAll() async {
            while inflight > 0 {
                let pending = Array(tasks.values)
                if pending.isEmpty {
                    await Task.yield()
                    if tasks.isEmpty {
                        inflight = 0
                        break
                    }
                    continue
                }
                for task in pending {
                    await task.value
                }
            }
            tasks.removeAll()
            generation.removeAll()
        }

        private func noteFinished() {
            inflight = max(0, inflight - 1)
        }
    }
}
