import DesignSystem
import SwiftUI

/// Unified notifications destination: permission, proactive channels, Shortcuts guide.
struct NotificationsSettingsView: View {
    @State private var status: NotificationAuthorizationStatus = .notDetermined
    @State private var isRequesting = false
    @State private var proactivePeekEnabled = ProactiveCoachPreferences.peekEnabled
    @State private var proactiveBannerEnabled = ProactiveCoachPreferences.bannerEnabled
    @State private var proactiveAutoChatEnabled = ProactiveCoachPreferences.autoChatEnabled
    @State private var proactivePushEnabled = ProactiveCoachPreferences.pushEnabled
    @State private var proactiveMilestonesEnabled = ProactiveCoachPreferences.milestonesEnabled
    @State private var usualMealNudgeEnabled = UsualMealPreferences.nudgeEnabled

    private let permissionService = NotificationPermissionService()

    private var isEnabled: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    var body: some View {
        List {
            Section {
                Text("Signal delivers a morning brief, a pre-workout prime, a post-workout summary, and usual-meal nudges when a meal slot is still empty. Morning briefs need HealthKit data; if the phone is locked, open Signal and the brief generates on the Dashboard.")
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .helmListRowChrome()
            }

            Section("Permission") {
                HelmStatusRow(
                    label: "Access",
                    value: statusLabel,
                    valueColor: isEnabled ? HelmColor.ready : HelmColor.fgMuted
                )
                .helmListRowChrome()

                if isEnabled {
                    Label("Notifications enabled", systemImage: "checkmark.circle.fill")
                        .helmType(.body, color: HelmColor.ready)
                        .helmListRowChrome()
                } else if status == .denied {
                    Text("Notifications are off in iOS Settings.")
                        .helmType(.body, color: HelmColor.fgSecondary)
                        .helmListRowChrome()
                    Button("Open Settings") {
                        openSettings()
                    }
                    .helmListRowChrome()
                } else {
                    Button(isRequesting ? "Requesting…" : "Enable Notifications") {
                        Task { await requestPermission() }
                    }
                    .disabled(isRequesting)
                    .helmListRowChrome()
                }
            }

            Section {
                Toggle("Set milestones (~25%)", isOn: $proactiveMilestonesEnabled)
                    .helmListRowChrome()
                    .onChange(of: proactiveMilestonesEnabled) { _, newValue in
                        ProactiveCoachPreferences.milestonesEnabled = newValue
                        HapticEngine.shared.play(.selection)
                    }
                Toggle("Peek on Ask coach bar", isOn: $proactivePeekEnabled)
                    .helmListRowChrome()
                    .onChange(of: proactivePeekEnabled) { _, newValue in
                        ProactiveCoachPreferences.peekEnabled = newValue
                        HapticEngine.shared.play(.selection)
                    }
                Toggle("Inline banner during workout", isOn: $proactiveBannerEnabled)
                    .helmListRowChrome()
                    .onChange(of: proactiveBannerEnabled) { _, newValue in
                        ProactiveCoachPreferences.bannerEnabled = newValue
                        HapticEngine.shared.play(.selection)
                    }
                Toggle("Auto-insert coach messages", isOn: $proactiveAutoChatEnabled)
                    .helmListRowChrome()
                    .onChange(of: proactiveAutoChatEnabled) { _, newValue in
                        ProactiveCoachPreferences.autoChatEnabled = newValue
                        HapticEngine.shared.play(.selection)
                    }
                Toggle("Push notifications", isOn: $proactivePushEnabled)
                    .helmListRowChrome()
                    .onChange(of: proactivePushEnabled) { _, newValue in
                        ProactiveCoachPreferences.pushEnabled = newValue
                        HapticEngine.shared.play(.selection)
                    }
            } header: {
                Text("Proactive coach")
            } footer: {
                Text("All proactive channels default on. Turn off any you do not want during workouts. Push still needs notification permission above.")
                    .helmType(.body, color: HelmColor.fgMuted)
            }

            Section {
                Toggle("Usual meal nudges", isOn: $usualMealNudgeEnabled)
                    .helmListRowChrome()
                    .onChange(of: usualMealNudgeEnabled) { _, newValue in
                        UsualMealPreferences.nudgeEnabled = newValue
                        HapticEngine.shared.play(.selection)
                        Task {
                            if newValue {
                                await ProactiveBootstrap.rescheduleUsualMeals()
                            } else {
                                await NutritionBootstrap.usualMealScheduler.cancelAll()
                            }
                        }
                    }
            } header: {
                Text("Food logging")
            } footer: {
                Text("Asks once per meal if that slot is still empty and you have a usual from recent logs. Yes logs it. Festival mode pauses these.")
                    .helmType(.body, color: HelmColor.fgMuted)
            }

            Section("Morning brief automation") {
                Label("Open Shortcuts and create a Personal Automation", systemImage: "1.circle")
                    .helmListRowChrome()
                Label("Choose Alarm → Is Dismissed, or When I unlock my iPhone", systemImage: "2.circle")
                    .helmListRowChrome()
                Label("Add Generate Morning Brief from Signal", systemImage: "3.circle")
                    .helmListRowChrome()
                Label("Turn off Ask Before Running so it fires automatically", systemImage: "4.circle")
                    .helmListRowChrome()
                Button("Open Shortcuts") {
                    guard let url = URL(string: "shortcuts://") else { return }
                    UIApplication.shared.open(url)
                    HapticEngine.shared.play(.selection)
                }
                .helmListRowChrome()
            }

            Section("Threshold insights") {
                Text("When a readiness contributor crosses a baseline threshold, Signal surfaces it on the Dashboard only. No push. Optional haptics live under Settings → Session.")
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .helmListRowChrome()
            }
        }
        .helmSettingsListChrome()
        .navigationTitle("Notifications")
        .task { await refreshStatus() }
        .onAppear {
            proactivePeekEnabled = ProactiveCoachPreferences.peekEnabled
            proactiveBannerEnabled = ProactiveCoachPreferences.bannerEnabled
            proactiveAutoChatEnabled = ProactiveCoachPreferences.autoChatEnabled
            proactivePushEnabled = ProactiveCoachPreferences.pushEnabled
            proactiveMilestonesEnabled = ProactiveCoachPreferences.milestonesEnabled
            usualMealNudgeEnabled = UsualMealPreferences.nudgeEnabled
        }
    }

    private var statusLabel: String {
        switch status {
        case .notDetermined: "Not requested yet"
        case .denied: "Denied in Settings"
        case .authorized: "Enabled"
        case .provisional: "Provisional"
        case .ephemeral: "Ephemeral"
        }
    }

    private func refreshStatus() async {
        status = await permissionService.currentStatus()
    }

    private func requestPermission() async {
        isRequesting = true
        defer { isRequesting = false }
        status = await permissionService.requestPermission()
        HapticEngine.shared.play(.selection)
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        HapticEngine.shared.play(.selection)
    }
}

#Preview("Notifications") {
    NavigationStack {
        NotificationsSettingsView()
    }
    .helmTheme()
}
