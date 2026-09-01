import AppIntents
import Core
import HealthKitIngest

enum UsualMealBucketEntity: String, AppEnum {
    case breakfast
    case lunch
    case dinner
    case snacks

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Meal")
    }

    static var caseDisplayRepresentations: [UsualMealBucketEntity: DisplayRepresentation] {
        [
            .breakfast: "Breakfast",
            .lunch: "Lunch",
            .dinner: "Dinner",
            .snacks: "Snacks"
        ]
    }

    var bucket: MealBucket {
        MealBucket(rawValue: rawValue) ?? .breakfast
    }
}

struct LogUsualMealIntent: AppIntent {
    static let title: LocalizedStringResource = "Log Usual Meal"
    static let description = IntentDescription(
        "Log your usual meal for an empty breakfast, lunch, or dinner slot."
    )
    static let openAppWhenRun = false

    @Parameter(title: "Meal")
    var meal: UsualMealBucketEntity

    init() {
        meal = .breakfast
    }

    init(meal: UsualMealBucketEntity) {
        self.meal = meal
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let outcome = await UsualMealIntentBootstrap.log(bucket: meal.bucket)
        switch outcome {
        case let .logged(name, _, _):
            return .result(dialog: "Logged \(name).")
        case let .alreadyLogged(bucket):
            return .result(dialog: "\(bucket.displayName) is already logged.")
        case let .noUsual(bucket):
            return .result(dialog: "No usual \(bucket.displayName.lowercased()) to log.")
        case let .failed(message):
            return .result(dialog: "Could not log: \(message)")
        }
    }
}
