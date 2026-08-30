import CoachLLM
import Core
import DesignSystem
import Diagnostics
import HealthKitIngest
import Persistence
import SwiftUI

struct SettingsView: View {
    @Bindable private var coordinator = HelmThemeCoordinator.shared
    @Bindable private var trainPreferences = TrainPreferences.shared
    @Bindable private var focusModePreferences = FocusModePreferences.shared
    @Bindable private var festivalModePreferences = FestivalModePreferences.shared
    @Bindable private var friendsRelease = FriendsReleasePreferences.shared

    @Environment(\.scenePhase) private var scenePhase

    @State private var healthStatusLabel = "…"
    @State private var notificationStatusLabel = "…"
    @State private var restNotificationNeedsPermission = false
    @State private var coachKeyStatusLabel = "…"
    @State private var memoryStatusLabel = "…"
    @State private var calendarStatusLabel = "…"
    @State private var watchStatusLabel = "…"
    @State private var spotifyStatusLabel = "…"
    @State private var showPlanBuilder = false
    @State private var advancedTapCount = 0

    var body: some View {
        NavigationStack {
            List {
                feedbackSection
                trainingSection
                nutritionSection
                coachSection
                connectionsSection
                notificationsSection
                trainSessionSection
                restTimerSection
                appearanceSection
                if friendsRelease.showsAdvanced {
                    batterySection
                }
                dataSection
                if friendsRelease.showsAdvanced {
                    advancedSection
                }
                versionSection
            }
            .helmSettingsListChrome()
            .navigationTitle("Settings")
            .sheet(isPresented: $showPlanBuilder) {
                PlanBuilderFlowView(hidesMaintenanceField: false)
            }
            .task {
                await AppTabRouter.shared.preferChromeOverContentLoad()
            }
            .onAppear {
                Task { await refreshStatusSummaries() }
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshStatusSummaries() }
            }
        }
    }

    private var feedbackSection: some View {
        Section {
            settingsLink("Send feedback", value: nil) {
                FeedbackView()
            }
        } footer: {
            Text("Bug or idea. Lands with Cam. Optionally attach coach chat.")
                .helmType(.body, color: HelmColor.fgMuted)
        }
    }

    private var trainingSection: some View {
        Section("Training") {
            settingsSheetButton("Training plan") {
                showPlanBuilder = true
            }
            settingsLink("Body Profile", value: nil) {
                BodyProfileSettingsView()
            }
            if friendsRelease.showsAdvanced {
                settingsLink("Plan details", value: nil) {
                    PhaseGoalSettingsView()
                }
                settingsLink("Custom Exercises", value: nil) {
                    SettingsCustomExercisesView()
                }
                settingsLink("Sources & Methodology", value: nil) {
                    SourcesMethodologyView()
                }
            }
        }
    }

    private var nutritionSection: some View {
        Section {
            settingsLink("Nutrition", value: nil) {
                NutritionSettingsView()
            }
        } header: {
            Text("Nutrition")
                .accessibilityLabel("Nutrition section")
        }
    }

    private var coachSection: some View {
        Section("Coach") {
            settingsLink("Coach settings", value: coachKeyStatusLabel) {
                CoachSettingsView(showsSecretFields: friendsRelease.showsAdvanced)
            }
            settingsLink("Coach Memory", value: memoryStatusLabel) {
                MemoryProfileEditorView()
            }
        }
    }

    private var connectionsSection: some View {
        Section("Connections") {
            settingsLink("Apple Health", value: healthStatusLabel) {
                AppleHealthSettingsView()
            }
            if friendsRelease.showsAdvanced {
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
    }

    private var notificationsSection: some View {
        Section {
            settingsLink("Notifications", value: notificationStatusLabel) {
                NotificationsSettingsView()
            }
        } header: {
            Text("Notifications")
                .accessibilityLabel("Notifications section")
        }
    }

    private var trainSessionSection: some View {
        Section {
            Toggle("Focus mode", isOn: $focusModePreferences.isFocusModeEnabled)
                .helmListRowChrome()
                .onChange(of: focusModePreferences.isFocusModeEnabled) { _, _ in
                    HapticEngine.shared.play(.selection)
                }

            Toggle("Manual rest timer", isOn: $trainPreferences.manualRestTimerEnabled)
                .helmListRowChrome()
                .onChange(of: trainPreferences.manualRestTimerEnabled) { _, _ in
                    HapticEngine.shared.play(.selection)
                }

            Toggle("Workout feedback", isOn: $trainPreferences.workoutFeedbackEnabled)
                .helmListRowChrome()
                .onChange(of: trainPreferences.workoutFeedbackEnabled) { _, _ in
                    HapticEngine.shared.play(.selection)
                }

            Toggle("Haptics", isOn: $coordinator.hapticsEnabled)
                .helmListRowChrome()
                .onChange(of: coordinator.hapticsEnabled) { _, _ in
                    HapticEngine.shared.play(.selection)
                }

            Toggle("Threshold insight haptics", isOn: $coordinator.thresholdInsightHapticsEnabled)
                .helmListRowChrome()
                .disabled(!coordinator.hapticsEnabled)
                .onChange(of: coordinator.thresholdInsightHapticsEnabled) { _, _ in
                    HapticEngine.shared.play(.selection)
                }
        } header: {
            Text("Session")
        } footer: {
            Text("Focus dimming hits set and meal rows while you log. Manual rest is a timer pill on the coach bar. Workout feedback is in-session confirmation sounds and cues. Threshold insights surface on the Dashboard when a readiness contributor crosses a baseline.")
                .helmType(.body, color: HelmColor.fgMuted)
        }
    }

    private var restTimerSection: some View {
        Section {
            Picker("Rest timer sound", selection: $trainPreferences.restTimerSoundID) {
                ForEach(RestTimerSoundID.allCases) { sound in
                    Text(sound.label).tag(sound)
                }
            }
            .helmListRowChrome()
            .onChange(of: trainPreferences.restTimerSoundID) { _, newValue in
                guard trainPreferences.restTimerVolume.isEnabled else { return }
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

            if restNotificationNeedsPermission {
                Button {
                    Task { await enableRestNotifications() }
                } label: {
                    Label("Enable notifications for rest alerts", systemImage: "bell.slash")
                }
                .helmListRowChrome()
                .foregroundStyle(HelmColor.destructive)
            }
        } header: {
            Text("Rest timer")
        } footer: {
            Text("Rings on speaker and headphones when rest ends, in app or with Signal in the background, and ignores the Silent switch. A notification is the backstop if iOS shuts Signal down first, so keep notifications enabled.")
                .helmType(.body, color: HelmColor.fgMuted)
        }
    }

    private var appearanceSection: some View {
        Section {
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

            if friendsRelease.showsAdvanced {
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

                Picker("Font", selection: $coordinator.prefersSystemFonts) {
                    Text("Bundled").tag(false)
                    Text("System").tag(true)
                }
                .pickerStyle(.segmented)
                .helmListRowChrome()
                .onChange(of: coordinator.prefersSystemFonts) { _, _ in
                    HapticEngine.shared.play(.selection)
                }
            }
        } header: {
            Text("Appearance")
        } footer: {
            if friendsRelease.showsAdvanced {
                Text("Signal is Tron HUD: grid void, neon brackets. Instrument and Data sheet stay as backups.")
                    .helmType(.body, color: HelmColor.fgMuted)
            }
        }
    }

    private var batterySection: some View {
        Section {
            Toggle("Festival mode", isOn: $festivalModePreferences.isFestivalModeEnabled)
                .helmListRowChrome()
                .onChange(of: festivalModePreferences.isFestivalModeEnabled) { _, newValue in
                    HapticEngine.shared.play(.selection)
                    Task {
                        await HealthKitBootstrap.setHealthKitObserving(!newValue)
                        if newValue {
                            await ProactiveBootstrap.cancelAllScheduled()
                        } else {
                            await ProactiveBootstrap.refreshScheduling()
                        }
                    }
                }
        } header: {
            Text("Battery")
        } footer: {
            Text("Festival mode pauses HealthKit background observers, Watch readiness pushes, and proactive notifications so Signal draws near-zero idle power. Leave it on when you don't need workout or health tracking. Nutrition logging still works from the Nutrition tab.")
                .helmType(.body, color: HelmColor.fgMuted)
        }
    }

    private var dataSection: some View {
        Section("Data") {
            settingsLink("Data & Backup", value: nil) {
                DataSafetyView()
            }
            if friendsRelease.showsAdvanced {
                settingsLink("Export health data", value: nil) {
                    SchemaV2ExportView()
                }
            }
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            settingsLink("Shortcuts setup", value: nil) {
                MorningBriefAutomationGuideView()
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

    private var versionSection: some View {
        Section {
            Text(versionLabel)
                .helmType(.body, color: HelmColor.fgMuted)
                .frame(maxWidth: .infinity)
                .onTapGesture { registerAdvancedTap() }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Tap seven times to show advanced settings")
        }
    }

    private func settingsSheetButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button {
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: HelmSpacing.sm)
                HelmIconView(.chevronRight, context: .inline)
                    .foregroundStyle(HelmColor.fgMuted)
            }
        }
        .foregroundStyle(HelmColor.fg)
        .helmListRowChrome()
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

        coachKeyStatusLabel = APIKeyStore().hasKey(kind: .gemini) ? "Ready" : "Unavailable"

        let memoryProfile = try? PersistenceBootstrap.persistenceStore.memoryProfile.load()
        if let profile = memoryProfile {
            let populated = [profile.baselinesSummary, profile.preferences, profile.standingConstraints,
                             profile.whatHasWorked, profile.injuryHistory, profile.trainingResponses,
                             profile.nutritionPatterns]
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            memoryStatusLabel = populated.isEmpty ? "Not set" : "Configured"
        } else {
            memoryStatusLabel = "Not set"
        }

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

    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Signal \(version) (\(build))"
    }

    private func registerAdvancedTap() {
        #if DEBUG
        return
        #else
        advancedTapCount += 1
        if advancedTapCount >= 7 {
            friendsRelease.advancedUnlocked = true
            HapticEngine.shared.play(.thresholdInsight)
            advancedTapCount = 0
        }
        #endif
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
