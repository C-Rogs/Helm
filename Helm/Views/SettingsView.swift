import DesignSystem
import Diagnostics
import SwiftUI

struct SettingsView: View {
    @Bindable private var coordinator = HelmThemeCoordinator.shared
    @Bindable private var trainPreferences = TrainPreferences.shared

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
                    .pickerStyle(.menu)
                    .onChange(of: coordinator.skin) { _, _ in
                        HapticEngine.shared.play(.selection)
                    }

                    Picker("Font", selection: $coordinator.prefersSystemFonts) {
                        Text("Helm").tag(false)
                        Text("System").tag(true)
                    }
                    .pickerStyle(.segmented)
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
                }

                Section("Feedback") {
                    Toggle("Haptics", isOn: $coordinator.hapticsEnabled)
                        .helmListRowChrome()
                    Toggle("Threshold insight haptics", isOn: $coordinator.thresholdInsightHapticsEnabled)
                        .helmListRowChrome()
                    Toggle("Workout feedback", isOn: $trainPreferences.workoutFeedbackEnabled)
                        .helmListRowChrome()
                    Toggle("Rest timer sound", isOn: $trainPreferences.restTimerSoundEnabled)
                        .helmListRowChrome()
                    Text("Boxing-ring bell when rest ends. Plays through headphones; ignores Silent switch when enabled.")
                        .helmType(.body, color: HelmColor.fgMuted)
                        .helmListRowChrome()
                }

                Section("Setup") {
                    NavigationLink("Health Access") {
                        HealthKitOnboardingStepView(showsFlowControls: false)
                            .navigationTitle("Health Access")
                    }
                    NavigationLink("Body Profile") {
                        BodyProfileSettingsView()
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

                Section("Training & Nutrition") {
                    NavigationLink("Training Plan") {
                        PhaseGoalSettingsView()
                    }
                    NavigationLink("Nutrition") {
                        NutritionSettingsView()
                    }
                }

                Section("Coach") {
                    NavigationLink("Coach") {
                        CoachSettingsView()
                    }
                    NavigationLink("Coach Memory") {
                        MemoryProfileEditorView()
                    }
                    NavigationLink("Sources & Methodology") {
                        SourcesMethodologyView()
                    }
                }

                Section("Connections") {
                    NavigationLink("HealthKit") {
                        HealthKitStatusView()
                    }
                    NavigationLink("Calendar Hints") {
                        CalendarHintStatusView()
                    }
                    NavigationLink("Watch Sync") {
                        WatchSyncStatusView()
                    }
                }

                Section("Data") {
                    NavigationLink("Data & Backup") {
                        DataSafetyView()
                    }
                    NavigationLink("Export health data") {
                        SchemaV2ExportView()
                    }
                }

                Section("Diagnostics") {
                    NavigationLink("Diagnostics") {
                        DiagnosticsView(environment: ExportEnvironmentFactory.current(
                            schemaVersion: PersistenceBootstrap.schemaVersion
                        ))
                    }
                    NavigationLink("Sleep diagnostics") {
                        SleepDiagnosticsView()
                    }
                    #if DEBUG
                    NavigationLink("Stored Data") {
                        DataBrowserView()
                    }
                    NavigationLink("In-Session Coach Debug") {
                        InSessionCoachDebugView()
                    }
                    #endif
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .listRowBackground(HelmListRowBackground())
            .navigationTitle("Settings")
            .helmScreenBackground()
        }
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

#Preview("Settings empty state") {
    ScrollView {
        HelmEmptyState(
            title: "No API key",
            message: "Add a coach API key in Setup to enable chat.",
            icon: .settings,
            actionTitle: "Open setup"
        ) {}
        .helmScreenPadding()
    }
    .helmTheme()
}

#Preview("Settings error") {
    ScrollView {
        HelmErrorState(
            title: "Sync failed",
            message: "Could not refresh HealthKit status.",
            onRetry: {}
        )
        .helmScreenPadding()
    }
    .helmTheme()
}
