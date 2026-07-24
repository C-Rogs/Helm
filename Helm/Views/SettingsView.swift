import DesignSystem
import Diagnostics
import SwiftUI

struct SettingsView: View {
    @Bindable private var coordinator = HelmThemeCoordinator.shared

    var body: some View {
        NavigationStack {
            List {
                Section("Appearance") {
                    Picker("Theme", selection: $coordinator.themeMode) {
                        ForEach(HelmThemeMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: coordinator.themeMode) { _, _ in
                        HapticEngine.shared.play(.selection)
                    }

                    Picker("Layout", selection: $coordinator.skin) {
                        ForEach(HelmSkin.selectableSkins) { skin in
                            Text(skin.label).tag(skin)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: coordinator.skin) { _, _ in
                        HapticEngine.shared.play(.selection)
                    }

                    Card {
                        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                            Text("Layout preview")
                                .helmType(.label)
                            Text("Cards switch between instrument panels and ruled data blocks.")
                                .helmType(.body, color: HelmColor.fgMuted)
                        }
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                }

                Section("Feedback") {
                    Toggle("Haptics", isOn: $coordinator.hapticsEnabled)
                    Toggle("Threshold insight haptics", isOn: $coordinator.thresholdInsightHapticsEnabled)
                }

                Section("Setup") {
                    NavigationLink("Health Access") {
                        HealthKitOnboardingStepView(showsFlowControls: false)
                            .navigationTitle("Health Access")
                    }
                    NavigationLink("Notifications") {
                        NotificationOnboardingStepView(showsFlowControls: false)
                            .navigationTitle("Notifications")
                    }
                    NavigationLink("Coach API Key") {
                        CoachKeyOnboardingStepView(showsFlowControls: false)
                            .navigationTitle("Coach API Key")
                    }
                    NavigationLink("Health Import") {
                        BackfillOnboardingStepView(showsFlowControls: false)
                            .navigationTitle("Health Import")
                    }
                    NavigationLink("Notifications & Shortcuts") {
                        MorningBriefAutomationGuideView()
                    }
                }

                Section {
                    NavigationLink("Training Plan") {
                        PhaseGoalSettingsView()
                    }
                    NavigationLink("Coach") {
                        CoachSettingsView()
                    }
                    NavigationLink("Coach Memory") {
                        MemoryProfileEditorView()
                    }
                    NavigationLink("Sources & Methodology") {
                        SourcesMethodologyView()
                    }
                    NavigationLink("HealthKit") {
                        HealthKitStatusView()
                    }
                    NavigationLink("Watch Sync") {
                        WatchSyncStatusView()
                    }
                    NavigationLink("Data & Backup") {
                        DataSafetyView()
                    }
                    NavigationLink("Export health data") {
                        SchemaV2ExportView()
                    }
                    NavigationLink("Diagnostics") {
                        DiagnosticsView(environment: ExportEnvironmentFactory.current(
                            schemaVersion: PersistenceBootstrap.schemaVersion
                        ))
                    }
                    #if DEBUG
                    NavigationLink("Stored Data") {
                        DataBrowserView()
                    }
                    #endif
                }
            }
            .listStyle(.plain)
            .listRowBackground(HelmColor.surface)
            .navigationTitle("Settings")
            .helmScreenBackground()
        }
    }
}

#Preview {
    SettingsView()
        .helmTheme()
}
