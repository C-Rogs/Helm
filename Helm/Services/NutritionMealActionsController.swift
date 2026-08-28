import Core
import DesignSystem
import HealthKitIngest
import Observation
import Persistence

@MainActor
@Observable
final class NutritionMealActionsController {
    enum PendingAction: Equatable, Identifiable {
        case logTemplate(MealTemplate)

        var id: String {
            switch self {
            case let .logTemplate(template):
                template.id.uuidString
            }
        }
    }

    struct CopyEntryContext: Equatable {
        let sourceDay: HelmDay
        let sourceBucket: MealBucket
    }

    private(set) var templates: [MealTemplate] = []
    private(set) var isSaving = false
    var pendingAction: PendingAction?
    var saveTemplateBucket: MealBucket?
    var copyEntryContext: CopyEntryContext?
    var errorMessage: String?

    private let mealRepeatService: MealRepeatService
    private let actionExecutor: HelmActionExecutor

    init(
        mealRepeatService: MealRepeatService,
        actionExecutor: HelmActionExecutor
    ) {
        self.mealRepeatService = mealRepeatService
        self.actionExecutor = actionExecutor
    }

    func reloadTemplates() {
        templates = (try? mealRepeatService.fetchTemplates()) ?? []
    }

    func beginSaveTemplate(for bucket: MealBucket) {
        saveTemplateBucket = bucket
    }

    func cancelSaveTemplate() {
        saveTemplateBucket = nil
    }

    func saveTemplate(name: String, bucket: MealBucket, helmDay: HelmDay) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter a template name."
            return
        }
        do {
            guard let template = try mealRepeatService.buildTemplate(
                name: trimmed,
                bucket: bucket,
                helmDay: helmDay
            ) else {
                errorMessage = "Nothing logged in \(bucket.displayName.lowercased()) to save."
                return
            }
            try mealRepeatService.saveTemplate(template)
            saveTemplateBucket = nil
            reloadTemplates()
            HapticEngine.shared.play(.mealConfirmed)
        } catch {
            errorMessage = "Could not save template. Try again."
        }
    }

    func beginLogTemplate(_ template: MealTemplate) {
        pendingAction = .logTemplate(template)
    }

    func cancelPendingAction() {
        pendingAction = nil
    }

    func confirmLogTemplate(_ template: MealTemplate, helmDay: HelmDay, today: HelmDay) async {
        isSaving = true
        defer { isSaving = false }
        do {
            let loggedAt = MealLogInstant.loggedAt(for: helmDay, bucket: template.bucket, today: today)
            _ = try await persist(
                .logTemplate(template, loggedAt: loggedAt, helmDay: helmDay)
            )
            pendingAction = nil
            HapticEngine.shared.play(.mealConfirmed)
        } catch {
            errorMessage = "Could not log template. Try again."
        }
    }

    func deleteTemplate(_ template: MealTemplate) {
        do {
            try mealRepeatService.deleteTemplate(id: template.id)
            reloadTemplates()
        } catch {
            errorMessage = "Could not delete template."
        }
    }

    func copyBucketToToday(bucket: MealBucket, today: HelmDay) async {
        let sourceDay = today.adding(days: -1)
        do {
            _ = try await persist(
                .copyMeal(HelmCopyMealCommand(
                    sourceDay: sourceDay,
                    sourceBucket: bucket,
                    targetDay: today
                ))
            )
            HapticEngine.shared.play(.mealConfirmed)
        } catch MealRepeatError.emptyBucket {
            errorMessage = "Nothing logged in \(bucket.displayName.lowercased()) yesterday."
        } catch {
            errorMessage = "Could not copy meal. Try again."
        }
    }

    func beginCopyEntry(sourceDay: HelmDay, sourceBucket: MealBucket) {
        copyEntryContext = CopyEntryContext(sourceDay: sourceDay, sourceBucket: sourceBucket)
    }

    func cancelCopyEntry() {
        copyEntryContext = nil
    }

    func confirmCopyEntry(targetDay: HelmDay, targetBucket: MealBucket) async {
        guard let context = copyEntryContext else { return }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await persist(
                .copyMeal(HelmCopyMealCommand(
                    sourceDay: context.sourceDay,
                    sourceBucket: context.sourceBucket,
                    targetDay: targetDay,
                    targetBucket: targetBucket
                ))
            )
            copyEntryContext = nil
            HapticEngine.shared.play(.mealConfirmed)
        } catch MealRepeatError.emptyBucket {
            errorMessage = "Nothing logged in \(context.sourceBucket.displayName.lowercased()) to copy."
        } catch {
            errorMessage = "Could not copy entry. Try again."
        }
    }

    func copyAllMeals(from sourceDay: HelmDay, to today: HelmDay) async {
        do {
            _ = try await persist(
                .copyAllMeals(sourceDay: sourceDay, targetDay: today)
            )
            HapticEngine.shared.play(.mealConfirmed)
        } catch MealRepeatError.emptySource {
            errorMessage = "No Signal meals logged on that day."
        } catch {
            errorMessage = "Could not copy meals. Try again."
        }
    }

    func copyYesterdayToToday(today: HelmDay) async {
        let sourceDay = today.adding(days: -1)
        do {
            _ = try await persist(
                .copyAllMeals(sourceDay: sourceDay, targetDay: today)
            )
            HapticEngine.shared.play(.mealConfirmed)
        } catch MealRepeatError.emptySource {
            errorMessage = "No meals logged yesterday."
        } catch {
            errorMessage = "Could not copy yesterday's meals. Try again."
        }
    }

    func dismissError() {
        errorMessage = nil
    }

    private func persist(_ command: HelmActionCommand) async throws -> HelmActionResult {
        try await HelmActionRuntime.persist(command, using: actionExecutor)
    }
}

extension NutritionMealActionsController {
    static func previewController() -> NutritionMealActionsController {
        let store = try! PersistenceStore.inMemory()
        let meals = ManualMealService()
        let repeatService = MealRepeatService(store: store, manualMealService: meals)
        return NutritionMealActionsController(
            mealRepeatService: repeatService,
            actionExecutor: HelmActionExecutor(
                manualMealService: meals,
                persistence: store,
                mealRepeatService: repeatService
            )
        )
    }
}
