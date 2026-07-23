import CoachLLM
import DesignSystem
import SwiftUI

struct CoachSettingsView: View {
    @State private var preferences = ProviderPreferencesStore()
    @State private var geminiKey = ""
    @State private var keyStatus = ""
    @State private var isSaving = false

    private let keyStore = APIKeyStore()

    var body: some View {
        Form {
            Section {
                Text("Choose the coach backend and store your Gemini API key on-device.")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Provider") {
                Picker("Coach provider", selection: Binding(
                    get: { preferences.selectedProvider },
                    set: { newValue in
                        preferences.selectedProvider = newValue
                        HapticEngine.shared.play(.selection)
                        refreshInstalledProvider()
                    }
                )) {
                    Text("Gemini").tag(ProviderKind.gemini)
                    Text("On-device").tag(ProviderKind.foundationModels)
                    Text("OpenRouter").tag(ProviderKind.openRouter)
                }
            }

            Section("Gemini API key") {
                SecureField("API key", text: $geminiKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button(isSaving ? "Saving…" : "Save key") {
                    saveKey()
                }
                .disabled(isSaving || geminiKey.isEmpty)

                if !keyStatus.isEmpty {
                    Text(keyStatus)
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.fgSecondary)
                }
            }
        }
        .navigationTitle("Coach")
        .helmScreenBackground()
        .onAppear {
            keyStatus = keyStore.hasKey(kind: .gemini) ? "Key saved in Keychain." : "No key saved yet."
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
        if keyStore.hasKey(kind: .gemini), preferences.selectedProvider == .gemini {
            ProviderRegistry.shared.installGeminiProvider(GeminiProvider(apiKeyStore: keyStore))
        }
    }
}

#Preview {
    NavigationStack {
        CoachSettingsView()
    }
    .helmTheme()
}
