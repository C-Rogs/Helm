import Foundation

@Observable
@MainActor
final class OnboardingCoordinator {
    var currentStep: OnboardingStep = .healthKit

    func advance() {
        guard let next = currentStep.next else { return }
        currentStep = next
    }

    func skip() {
        advance()
    }

    var isOnFinalStep: Bool {
        currentStep == .shortcuts
    }
}
