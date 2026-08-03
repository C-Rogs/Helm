import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case healthKit
    case bodyProfile
    case notifications
    case coachKey
    case trainingPlan
    case backfill
    case shortcuts

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome to Signal"
        case .healthKit: "Health data"
        case .bodyProfile: "Body profile"
        case .notifications: "Notifications"
        case .coachKey: "Coach"
        case .trainingPlan: "Training plan"
        case .backfill: "Import history"
        case .shortcuts: "Shortcuts"
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
        case .coachKey:
            "Add a Gemini API key for coach narration. Engine-only mode works without one."
        case .trainingPlan:
            "Set your phase and goal so today's session is prescribed."
        case .backfill:
            "Import the last six months to seed readiness baselines."
        case .shortcuts:
            "Automate your morning brief from Shortcuts when you are ready."
        }
    }

    var settingsLabel: String {
        switch self {
        case .welcome: "Welcome"
        case .healthKit: "Health Access"
        case .bodyProfile: "Body Profile"
        case .notifications: "Notifications"
        case .coachKey: "Coach API Key"
        case .trainingPlan: "Training Plan"
        case .backfill: "Health Import"
        case .shortcuts: "Shortcuts Setup"
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}
