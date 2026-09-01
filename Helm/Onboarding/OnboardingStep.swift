import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case healthKit
    case bodyProfile
    case notifications
    case trainingPlan
    case hevyImport
    case backfill

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome to Signal"
        case .healthKit: "Health data"
        case .bodyProfile: "Body profile"
        case .notifications: "Notifications"
        case .trainingPlan: "Training plan"
        case .hevyImport: "Hevy import"
        case .backfill: "Import history"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            "Your readiness instrument. One arc, one score, one plan for today."
        case .healthKit:
            "Signal reads Apple Health to compute readiness, training load, and nutrition."
        case .bodyProfile:
            "Confirm weight, height, sex, and date of birth so Signal can estimate maintenance calories."
        case .notifications:
            "Rest timers and future briefs use local notifications."
        case .trainingPlan:
            "Draft plan options, ask for a different split, and preview an example session."
        case .hevyImport:
            "Import the last 90 days from a Hevy CSV so recents, previous weights, and PRs are already there."
        case .backfill:
            "Import the last six months to seed readiness baselines."
        }
    }

    var settingsLabel: String {
        switch self {
        case .welcome: "Welcome"
        case .healthKit: "Health Access"
        case .bodyProfile: "Body Profile"
        case .notifications: "Notifications"
        case .trainingPlan: "Training Plan"
        case .hevyImport: "Hevy Import"
        case .backfill: "Health Import"
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}
