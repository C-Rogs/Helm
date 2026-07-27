import Foundation

@Observable
@MainActor
final class OnboardingCoordinator {
    var currentStep: OnboardingStep = .welcome

    var canGoBack: Bool {
        currentStep.previous != nil
    }

    func advance() {
        guard let next = currentStep.next else { return }
        currentStep = next
    }

    func goBack() {
        guard let previous = currentStep.previous else { return }
        currentStep = previous
    }

    func skip() {
        advance()
    }

    var isOnFinalStep: Bool {
        currentStep == .shortcuts
    }
}
