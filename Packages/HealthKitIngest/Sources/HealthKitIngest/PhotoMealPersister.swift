import Core
import Diagnostics
import Foundation
import OSLog

private let photoMealPersistLog = Logger(subsystem: "com.cameronro.helm", category: "NutritionKit")

/// HealthKit + GRDB persist for a confirmed photo estimate.
public struct PhotoMealPersister: Sendable {
    private let writer: any MealHealthKitWriting
    private let localStore: PhotoMealLocalStore?
    private let hkWrites: MealHealthKitWriteQueue

    public init(
        writer: any MealHealthKitWriting = MealHealthKitWriter(),
        localStore: PhotoMealLocalStore? = nil,
        hkWrites: MealHealthKitWriteQueue = MealHealthKitWriteQueue()
    ) {
        self.writer = writer
        self.localStore = localStore
        self.hkWrites = hkWrites
    }

    public func flushHealthKitWrites() async {
        await hkWrites.waitAll()
    }

    public func confirm(
        estimate: MealEstimate,
        name: String,
        bucket: MealBucket = .snacks,
        loggedAt: Date = Date(),
        helmDay: HelmDay? = nil,
        mealID: String = UUID().uuidString
    ) async throws -> SavedMealSamples {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = trimmedName.isEmpty ? estimate.description : trimmedName
        let request = MealWriteRequest(
            mealID: mealID.lowercased(),
            name: resolvedName,
            loggedAt: loggedAt,
            helmDay: helmDay,
            caloriesKcal: estimate.caloriesKcal,
            proteinG: estimate.proteinG,
            carbsG: estimate.carbsG,
            fatG: estimate.fatG,
            lineItems: estimate.lineItems,
            mealSource: HelmHealthKitMetadata.mealSourcePhoto
        )

        guard let localStore else {
            do {
                let saved = try await writer.saveMeal(request)
                photoMealPersistLog.debug("Photo meal saved mealID=\(saved.mealID, privacy: .public)")
                return saved
            } catch {
                photoMealPersistLog.error(
                    "Photo meal write failed: \(String(describing: type(of: error)), privacy: .public)"
                )
                Task {
                    await DiagnosticsLog.shared.capture(
                        error: error,
                        category: .nutritionKit,
                        message: "Photo meal HealthKit write failed"
                    )
                }
                throw error
            }
        }

        let localOnly = SavedMealSamples.localOnly(mealID: mealID)
        try localStore.recordSavedMeal(request, saved: localOnly, bucket: bucket)
        let mealUUID = UUID(uuidString: request.mealID) ?? localOnly.energy.id
        let writer = self.writer
        await hkWrites.enqueue(mealID: request.mealID) {
            await Self.writeHealthKitInBackground(
                writer: writer,
                localStore: localStore,
                request: request,
                mealUUID: mealUUID
            )
        }
        photoMealPersistLog.debug("Photo meal saved mealID=\(localOnly.mealID, privacy: .public) hk=deferred")
        return localOnly
    }

    private static func writeHealthKitInBackground(
        writer: any MealHealthKitWriting,
        localStore: PhotoMealLocalStore,
        request: MealWriteRequest,
        mealUUID: UUID
    ) async {
        do {
            let saved = try await writer.saveMeal(request)
            if try localStore.fetchMeal(id: mealUUID) != nil {
                try localStore.attachHealthKitSamples(mealID: mealUUID, saved: saved)
            } else {
                try await writer.deleteMeal(mealID: request.mealID.lowercased())
            }
        } catch {
            photoMealPersistLog.error(
                "Photo meal HealthKit write failed: \(String(describing: type(of: error)), privacy: .public)"
            )
            Task {
                await DiagnosticsLog.shared.capture(
                    error: error,
                    category: .nutritionKit,
                    message: "Photo meal HealthKit write failed; saving locally only"
                )
            }
        }
    }
}
