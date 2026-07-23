import CoachLLM
import DesignSystem
import SwiftUI

struct CoachKeyOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 3
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onSkip: () -> Void = {}

    @State private var geminiKey = ""
    @State private var keyStatus = ""
    @State private var isSaving = false

    private let keyStore = APIKeyStore()

    var body: some View {
        OnboardingStepChrome(
            step: .coachKey,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            onPrimary: onContinue,
            onSkip: onSkip
        ) {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                SecureField("Gemini API key", text: $geminiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(HelmSpacing.md)
                    .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.sm))

                Button(isSaving ? "Saving…" : "Save key") {
                    saveKey()
                }
                .buttonStyle(.helmPrimary)
                .disabled(isSaving || geminiKey.isEmpty)

                if !keyStatus.isEmpty {
                    Text(keyStatus)
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.fgSecondary)
                }
            }
        }
        .onAppear {
            keyStatus = keyStore.hasKey(kind: .gemini) ? "Key saved in Keychain." : "Optional. Skip to use engine-only mode."
        }
    }

    private func saveKey() {
        isSaving = true
        defer { isSaving = false }
        do {
            try keyStore.save(geminiKey, kind: .gemini)
            keyStatus = "Key saved in Keychain."
            geminiKey = ""
            HapticEngine.shared.play(.selection)
            refreshInstalledProvider()
        } catch {
            keyStatus = "Could not save key."
            HapticEngine.shared.play(.clampRejected)
        }
    }

    @MainActor
    private func refreshInstalledProvider() {
        ProviderRegistry.shared.resetGeminiProvider()
        if keyStore.hasKey(kind: .gemini) {
            ProviderRegistry.shared.installGeminiProvider(GeminiProvider(apiKeyStore: keyStore))
        }
    }
}

#Preview {
    CoachKeyOnboardingStepView()
        .helmTheme()
}
