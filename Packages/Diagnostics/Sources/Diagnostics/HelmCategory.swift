public enum HelmCategory: String, Sendable, CaseIterable {
    case persistence = "Persistence"
    case healthKitIngest = "HealthKitIngest"
    case readinessKit = "ReadinessKit"
    case planKit = "PlanKit"
    case nutritionKit = "NutritionKit"
    case patternKit = "PatternKit"
    case coachLLM = "CoachLLM"
    case logger = "Logger"
    case appIntents = "AppIntents"
    case watch = "Watch"
    case ui = "UI"
}

public enum HelmSubsystem {
    public static let value = "com.cameronro.helm"
}
