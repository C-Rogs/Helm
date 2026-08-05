import CoachLLM
import Core
import DesignSystem
import Diagnostics
import HealthKitIngest
import SwiftUI

struct SettingsView: View {
    @Bindable private var coordinator = HelmThemeCoordinator.shared
    @Bindable private var trainPreferences = TrainPreferences.shared
    @Bindable private var focusModePreferences = FocusModePreferences.shared

    @State private var healthStatusLabel = "…"
    @State private var notificationStatusLabel = "…"
    @State private var restNotificationNeedsPermission = false
    @State private var coachKeyStatusLabel = "…"
    @State private var calendarStatusLabel = "…"
    @State private var watchStatusLabel = "…"
    @State private var spotifyStatusLabel = "…"

    var body: some View {
        NavigationStack {
            List {
                appearanceSection
                feedbackSection
                trainSoundsSection
                trainingSection
                coachSection
                connectionsSection
                dataSection
                advancedSection
            }
            .helmSettingsListChrome()
            .navigationTitle("Settings")
            .task { await refreshStatusSummaries() }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $coordinator.themeMode) {
                ForEach(HelmThemeMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .helmListRowChrome()
            .onChange(of: coordinator.themeMode) { _, _ in
                HapticEngine.shared.play(.selection)
            }

            Picker("Layout", selection: $coordinator.skin) {
                ForEach(HelmSkin.selectableSkins) { skin in
                    Text(skin.label).tag(skin)
                }
            }
            .pickerStyle(.menu)
            .helmListRowChrome()
            .onChange(of: coordinator.skin) { _, _ in
                HapticEngine.shared.play(.selection)
            }

            Picker(
                "Accent",
                selection: Binding(
                    get: { coordinator.accentPreset },
                    set: { coordinator.accentSource = .preset($0) }
                )
            ) {
                ForEach(HelmAccentPreset.allCases) { preset in
                    Label {
                        Text(preset.label)
                    } icon: {
                        Circle()
                            .fill(preset.swatchColor)
                            .frame(width: 14, height: 14)
                            .overlay {
                                Circle()
                                    .strokeBorder(HelmColor.hairline, lineWidth: 1)
                            }
                    }
                    .tag(preset)
                }
            }
            .pickerStyle(.menu)
            .helmListRowChrome()
            .onChange(of: coordinator.accentSource) { _, _ in
                HapticEngine.shared.play(.selection)
            }

            Picker("Font", selection: $coordinator.prefersSystemFonts) {
                Text("Bundled").tag(false)
                Text("System").tag(true)
            }
            .pickerStyle(.segmented)
            .helmListRowChrome()
            .onChange(of: coordinator.prefersSystemFonts) { _, _ in
                HapticEngine.shared.play(.selection)
            }

            HelmRuledRow {
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    Text("Layout preview")
                        .helmType(.label)
                    Text("Signal is Tron HUD: grid void, neon brackets. Instrument and Data sheet stay as backups.")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            Toggle("Focus mode", isOn: $focusModePreferences.isFocusModeEnabled)
                .helmListRowChrome()
                .onChange(of: focusModePreferences.isFocusModeEnabled) { _, _ in
                    HapticEngine.shared.play(.selection)
                }

            Text("Dims inactive set and meal rows while you log, so the active entry stays front and center.")
                .helmType(.body, color: HelmColor.fgMuted)
                .helmListRowChrome()
        }
    }

    private var feedbackSection: some View {
        Section {
            Toggle("Haptics", isOn: $coordinator.hapticsEnabled)
                .helmListRowChrome()
                .onChange(of: coordinator.hapticsEnabled) { _, _ in
                    HapticEngine.shared.play(.selection)
                }
            Toggle("Threshold insight haptics", isOn: $coordinator.thresholdInsightHapticsEnabled)
                .helmListRowChrome()
                .onChange(of: coordinator.thresholdInsightHapticsEnabled) { _, _ in
                    HapticEngine.shared.play(.selection)
                }
            Toggle("Workout feedback", isOn: $trainPreferences.workoutFeedbackEnabled)
                .helmListRowChrome()
                .onChange(of: trainPreferences.workoutFeedbackEnabled) { _, _ in
                    HapticEngine.shared.play(.selection)
                }
        } header: {
            Text("Feedback")
        } footer: {
            Text("Threshold insights surface on the Dashboard when a readiness contributor crosses a baseline. Workout feedback covers in-session confirmation sounds and cues.")
                .helmType(.body, color: HelmColor.fgMuted)
        }
    }

    private var trainSoundsSection: some View {
        Section("Train sounds") {
            Picker("Rest timer sound", selection: $trainPreferences.restTimerSoundID) {
                ForEach(RestTimerSoundID.allCases) { sound in
                    Text(sound.label).tag(sound)
                }
            }
            .helmListRowChrome()
            .onChange(of: trainPreferences.restTimerSoundID) { _, newValue in
                previewRestTimerSound(soundID: newValue)
            }

            Picker("Rest timer volume", selection: $trainPreferences.restTimerVolume) {
                ForEach(RestTimerVolumeLevel.allCases) { level in
                    Text(level.label).tag(level)
                }
            }
            .helmListRowChrome()
            .onChange(of: trainPreferences.restTimerVolume) { _, newValue in
                HapticEngine.shared.play(.selection)
                if newValue.isEnabled {
                    previewRestTimerSound(volume: newValue)
                }
            }

            Button {
                previewRestTimerSound()
            } label: {
                Label("Preview sound", systemImage: "speaker.wave.2")
            }
            .helmListRowChrome()

            Text("Rings on speaker and headphones when rest ends, in app or with Helm in the background, and ignores the Silent switch. A notification is the backstop if iOS shuts Helm down first, so keep notifications enabled.")
                .helmType(.body, color: HelmColor.fgMuted)
                .helmListRowChrome()

            if restNotificationNeedsPermission {
                Button {
                    Task { await enableRestNotifications() }
                } label: {
                    Label("Enable notifications for rest alerts", systemImage: "bell.slash")
                }
                .helmListRowChrome()
                .foregroundStyle(HelmColor.destructive)
            }
        }
    }

    private var trainingSection: some View {
        Section("Training & Nutrition") {
            Toggle("Manual rest timer", isOn: $trainPreferences.manualRestTimerEnabled)
                .helmListRowChrome()
                .onChange(of: trainPreferences.manualRestTimerEnabled) { _, _ in
                    HapticEngine.shared.play(.selection)
                }

            Text("Shows a timer pill on the coach bar during workouts for starting a custom rest countdown.")
                .helmType(.body, color: HelmColor.fgMuted)
                .helmListRowChrome()

            settingsLink("Body Profile", value: nil) {
                BodyProfileSettingsView()
            }
            settingsLink("Training Plan", value: nil) {
                PhaseGoalSettingsView()
            }
            settingsLink("Nutrition", value: nil) {
                NutritionSettingsView()
            }
            settingsLink("Sources & Methodology", value: nil) {
                SourcesMethodologyView()
            }
        }
    }

    private var coachSection: some View {
        Section("Coach") {
            settingsLink("Coach settings", value: coachKeyStatusLabel) {
                CoachSettingsView()
            }
            settingsLink("Coach Memory", value: nil) {
                MemoryProfileEditorView()
            }
            settingsLink("Notifications", value: notificationStatusLabel) {
                NotificationsSettingsView()
            }
        }
    }

    private var connectionsSection: some View {
        Section("Connections") {
            settingsLink("Apple Health", value: healthStatusLabel) {
                AppleHealthSettingsView()
            }
            settingsLink("Spotify", value: spotifyStatusLabel) {
                SpotifySettingsView()
            }
            settingsLink("Calendar Hints", value: calendarStatusLabel) {
                CalendarHintStatusView()
            }
            settingsLink("Watch Sync", value: watchStatusLabel) {
                WatchSyncStatusView()
            }
        }
    }

    private var dataSection: some View {
        Section("Data") {
            settingsLink("Data & Backup", value: nil) {
                DataSafetyView()
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            settingsLink("Export health data", value: nil) {
                SchemaV2ExportView()
            }
            settingsLink("Diagnostics", value: nil) {
                DiagnosticsView(environment: ExportEnvironmentFactory.current(
                    schemaVersion: PersistenceBootstrap.schemaVersion
                ))
            }
            settingsLink("Sleep diagnostics", value: nil) {
                SleepDiagnosticsView()
            }
            #if DEBUG
            settingsLink("Stored Data", value: nil) {
                DataBrowserView()
            }
            settingsLink("In-Session Coach Debug", value: nil) {
                InSessionCoachDebugView()
            }
            #endif
        }
    }

    private func settingsLink<Destination: View>(
        _ title: String,
        value: String?,
        @ViewBuilder destination: () -> Destination
    ) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: HelmSpacing.sm)
                if let value {
                    Text(value)
                        .helmType(.body, color: HelmColor.fgMuted)
                }
            }
        }
        .helmListRowChrome()
    }

    private func previewRestTimerSound(
        soundID: RestTimerSoundID? = nil,
        volume: RestTimerVolumeLevel? = nil
    ) {
        HapticEngine.shared.play(.selection)
        let resolvedVolume = volume ?? trainPreferences.restTimerVolume
        let previewVolume: RestTimerVolumeLevel = resolvedVolume.isEnabled ? resolvedVolume : .normal
        RestTimerSoundPlayer.shared.play(
            soundID: soundID ?? trainPreferences.restTimerSoundID,
            volume: previewVolume
        )
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    private func enableRestNotifications() async {
        let service = NotificationPermissionService()
        let status = await service.currentStatus()
        if status == .notDetermined {
            let updated = await service.requestPermission()
            restNotificationNeedsPermission = updated == .denied || updated == .notDetermined
            notificationStatusLabel = notificationSummary(updated)
            if updated == .denied {
                openSystemSettings()
            }
            return
        }
        openSystemSettings()
    }

    @MainActor
    private func refreshStatusSummaries() async {
        let health = await HealthKitBootstrap.healthKitIngest.currentStatus()
        healthStatusLabel = health.connectionState.rawValue

        let notificationStatus = await NotificationPermissionService().currentStatus()
        notificationStatusLabel = notificationSummary(notificationStatus)
        restNotificationNeedsPermission = notificationStatus == .denied || notificationStatus == .notDetermined

        coachKeyStatusLabel = APIKeyStore().hasKey(kind: .gemini) ? "Key saved" : "No key"

        calendarStatusLabel = calendarSummary(CalendarHintBootstrap.service.currentStatus())

        let coordinator = WatchReadinessBootstrap.coordinator
        coordinator.refreshPairingFlags()
        watchStatusLabel = watchSummary(coordinator)

        let spotify = SpotifyAppRemoteService.shared
        spotify.configure()
        spotifyStatusLabel = spotify.isAuthorized ? "Linked" : "Not linked"
    }

    private func notificationSummary(_ status: NotificationAuthorizationStatus) -> String {
        switch status {
        case .authorized, .provisional, .ephemeral: "Enabled"
        case .denied: "Denied"
        case .notDetermined: "Not requested"
        }
    }

    private func calendarSummary(_ status: CalendarAuthorizationStatus) -> String {
        switch status {
        case .authorized: "Allowed"
        case .denied: "Denied"
        case .restricted: "Restricted"
        case .notDetermined: "Not requested"
        }
    }

    private func watchSummary(_ coordinator: WatchSessionCoordinator) -> String {
        if coordinator.isCompanionLive { return "Live" }
        if coordinator.isReachable { return "Reachable" }
        return "Reconnect"
    }
}

#Preview("Settings signal") {
    SettingsView()
        .helmTheme()
        .environment(\.helmSkin, .signal)
}

#Preview("Settings instrument") {
    SettingsView()
        .helmTheme()
        .environment(\.helmSkin, .instrument)
}

#Preview("Settings data sheet") {
    SettingsView()
        .helmTheme()
        .environment(\.helmSkin, .dataSheet)
}

#Preview("Settings accessibility") {
    SettingsView()
        .helmTheme()
        .dynamicTypeSize(.accessibility5)
}
