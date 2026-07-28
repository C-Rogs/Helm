import CoachLLM
import DesignSystem
import SwiftUI

struct CoachSettingsView: View {
    @State private var preferences = ProviderPreferencesStore()
    @State private var geminiKey = ""
    @State private var openRouterKey = ""
    @State private var keyStatus = ""
    @State private var openRouterStatus = ""
    @State private var isSaving = false
    @State private var isSavingOpenRouter = false
    @State private var isProvisioningOpenRouter = false
    @State private var photoVisionPreferences = MealVisionPreferencesStore()
    @State private var coachDisplayName = CoachDisplayNameStore.name
    @State private var allowsParallelCoaches = CoachActivityGate.shared.allowsParallelCoaches
    @State private var proactivePeekEnabled = ProactiveCoachPreferences.peekEnabled
    @State private var proactiveBannerEnabled = ProactiveCoachPreferences.bannerEnabled
    @State private var proactiveAutoChatEnabled = ProactiveCoachPreferences.autoChatEnabled
    @State private var proactivePushEnabled = ProactiveCoachPreferences.pushEnabled

    private let keyStore = APIKeyStore()
    private let openRouterMetadata = OpenRouterKeyMetadataStore()

    var body: some View {
        Form {
            Section {
                Text("Coach chat uses Gemini. OpenRouter powers photo meal vision below.")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Coach name") {
                TextField("Display name", text: $coachDisplayName)
                    .textInputAutocapitalization(.words)
                    .onChange(of: coachDisplayName) { _, newValue in
                        CoachDisplayNameStore.name = newValue
                    }
                Text("Used in Chat and in-session coach.")
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Concurrency") {
                Toggle("Allow Chat and workout coach at the same time", isOn: $allowsParallelCoaches)
                    .onChange(of: allowsParallelCoaches) { _, newValue in
                        CoachActivityGate.shared.allowsParallelCoaches = newValue
                    }
            }

            Section("Proactive coach") {
                Toggle("Peek on Ask coach bar", isOn: $proactivePeekEnabled)
                    .onChange(of: proactivePeekEnabled) { _, newValue in
                        ProactiveCoachPreferences.peekEnabled = newValue
                    }
                Toggle("Inline banner during workout", isOn: $proactiveBannerEnabled)
                    .onChange(of: proactiveBannerEnabled) { _, newValue in
                        ProactiveCoachPreferences.bannerEnabled = newValue
                    }
                Toggle("Auto-insert coach messages", isOn: $proactiveAutoChatEnabled)
                    .onChange(of: proactiveAutoChatEnabled) { _, newValue in
                        ProactiveCoachPreferences.autoChatEnabled = newValue
                    }
                Toggle("Push notifications", isOn: $proactivePushEnabled)
                    .onChange(of: proactivePushEnabled) { _, newValue in
                        ProactiveCoachPreferences.pushEnabled = newValue
                    }
                Text("All proactive channels are on by default. Turn off any you do not want during workouts.")
                    .font(HelmTypography.caption)
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

            Section("Photo meal vision") {
                Picker("Photo model", selection: Binding(
                    get: { photoVisionPreferences.backendPreference },
                    set: { newValue in
                        photoVisionPreferences.backendPreference = newValue
                        HapticEngine.shared.play(.selection)
                    }
                )) {
                    Text("Auto").tag(MealVisionBackendPreference.auto)
                    Text("Gemini").tag(MealVisionBackendPreference.gemini)
                    Text("OpenRouter").tag(MealVisionBackendPreference.openRouter)
                }

                Picker("Photo accuracy", selection: Binding(
                    get: { photoVisionPreferences.qualityPreference },
                    set: { newValue in
                        photoVisionPreferences.qualityPreference = newValue
                        HapticEngine.shared.play(.selection)
                    }
                )) {
                    Text("Accurate (slower)").tag(MealVisionQualityPreference.accurate)
                    Text("Fast").tag(MealVisionQualityPreference.fast)
                }

                Text("Auto prefers Gemini when a key is present, otherwise OpenRouter. Accurate uses the stronger Gemini model first. Macro math stays on-device via CoFID.")
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("OpenRouter (TestFlight)") {
                Text(
                    "Release builds can auto-provision a capped, free-models-only key via the personal Coacher worker. Friends-only: the worker shared secret ships in the binary, not for App Store."
                )
                .font(HelmTypography.caption)
                .foregroundStyle(HelmColor.fgSecondary)

                if keyStore.hasKey(kind: .openRouter) {
                    Text("OpenRouter key saved in Keychain.")
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.fgSecondary)
                }

                #if !DEBUG
                Button(isProvisioningOpenRouter ? "Provisioning…" : "Request cloud key") {
                    provisionOpenRouterKey()
                }
                .disabled(isProvisioningOpenRouter)
                #endif

                SecureField("Or paste OpenRouter API key", text: $openRouterKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button(isSavingOpenRouter ? "Saving…" : "Save OpenRouter key") {
                    saveOpenRouterKey()
                }
                .disabled(isSavingOpenRouter || openRouterKey.isEmpty)

                if !openRouterStatus.isEmpty {
                    Text(openRouterStatus)
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.fgSecondary)
                }
            }
        }
        .navigationTitle("Coach")
        .helmScreenBackground()
        .onAppear {
            coachDisplayName = CoachDisplayNameStore.name
            allowsParallelCoaches = CoachActivityGate.shared.allowsParallelCoaches
            proactivePeekEnabled = ProactiveCoachPreferences.peekEnabled
            proactiveBannerEnabled = ProactiveCoachPreferences.bannerEnabled
            proactiveAutoChatEnabled = ProactiveCoachPreferences.autoChatEnabled
            proactivePushEnabled = ProactiveCoachPreferences.pushEnabled
            if geminiKey.isEmpty {
                geminiKey = keyStore.displayValue(for: .gemini)
            }
            if openRouterKey.isEmpty {
                openRouterKey = keyStore.displayValue(for: .openRouter)
            }
            keyStatus = keyStore.hasKey(kind: .gemini) ? "Key saved in Keychain." : "No key saved yet."
            refreshOpenRouterStatus()
        }
    }

    private func saveKey() {
        isSaving = true
        defer { isSaving = false }
        do {
            try keyStore.save(geminiKey, kind: .gemini)
            keyStatus = "Key saved in Keychain."
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

    private func saveOpenRouterKey() {
        isSavingOpenRouter = true
        defer { isSavingOpenRouter = false }
        do {
            try keyStore.save(openRouterKey, kind: .openRouter)
            openRouterMetadata.clear()
            openRouterStatus = "OpenRouter key saved in Keychain."
            HapticEngine.shared.play(.selection)
            refreshOpenRouterStatus()
        } catch {
            openRouterStatus = "Could not save OpenRouter key."
            HapticEngine.shared.play(.clampRejected)
        }
    }

    private func provisionOpenRouterKey() {
        isProvisioningOpenRouter = true
        Task {
            let result = await OpenRouterKeyProvisioner.provisionIfNeeded()
            await MainActor.run {
                isProvisioningOpenRouter = false
                switch result {
                case .provisioned(let wasNew):
                    openRouterStatus = wasNew
                        ? "Cloud key provisioned and saved."
                        : "Existing cloud key restored."
                    openRouterKey = keyStore.displayValue(for: .openRouter)
                    HapticEngine.shared.play(.selection)
                case .alreadyPresent:
                    openRouterStatus = "OpenRouter key already in Keychain."
                case .notConfigured:
                    openRouterStatus = "Key service URL not configured in this build."
                case .failed(let message):
                    openRouterStatus = message
                    HapticEngine.shared.play(.clampRejected)
                case .skippedDebugBuild:
                    openRouterStatus = "Auto-provision runs in Release builds only."
                }
                refreshOpenRouterStatus()
            }
        }
    }

    private func refreshOpenRouterStatus() {
        if openRouterStatus.isEmpty {
            openRouterStatus = keyStore.hasKey(kind: .openRouter)
                ? "OpenRouter key saved in Keychain."
                : "No OpenRouter key yet."
        }
    }
}

#Preview {
    NavigationStack {
        CoachSettingsView()
    }
    .helmTheme()
}
