import Foundation

enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome
    case trainingPlan
    case bodyProfile
    case cloudFeatures
    case healthKit
    case notifications

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .welcome: "Welcome to Signal"
        case .trainingPlan: "Your plan"
        case .bodyProfile: "Body profile"
        case .cloudFeatures: "Cloud features"
        case .healthKit: "Health data"
        case .notifications: "You're ready"
        }
    }

    var subtitle: String {
        switch self {
        case .welcome:
            "Readiness, training, and nutrition in one closed loop. Your body tells Signal the plan."
        case .trainingPlan:
            "Set experience, days, equipment, and phase. Signal drafts the split and today's session."
        case .bodyProfile:
            "Weight, height, sex, and date of birth seed maintenance calories."
        case .cloudFeatures:
            "Choose whether Signal can use cloud coaching and connected features. Local tracking always stays on your phone."
        case .healthKit:
            "Apple Health feeds readiness and training load so the plan can adapt."
        case .notifications:
            "Optional rest timers and briefs. Then open Train for your first session."
        }
    }

    var settingsLabel: String {
        switch self {
        case .welcome: "Welcome"
        case .trainingPlan: "Training Plan"
        case .bodyProfile: "Body Profile"
        case .cloudFeatures: "Cloud Features"
        case .healthKit: "Health Access"
        case .notifications: "Notifications"
        }
    }

    var next: OnboardingStep? {
        OnboardingStep(rawValue: rawValue + 1)
    }

    var previous: OnboardingStep? {
        OnboardingStep(rawValue: rawValue - 1)
    }
}
