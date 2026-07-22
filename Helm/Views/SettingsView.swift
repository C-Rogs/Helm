import DesignSystem
import Diagnostics
import SwiftUI

struct SettingsView: View {
    @State private var coordinator = HelmThemeCoordinator.shared

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
                }

                Section("Feedback") {
                    Toggle("Haptics", isOn: $coordinator.hapticsEnabled)
                }

                Section {
                    NavigationLink("HealthKit") {
                        HealthKitStatusView()
                    }
                    NavigationLink("Watch Sync") {
                        WatchSyncStatusView()
                    }
                    NavigationLink("Data & Backup") {
                        DataSafetyView()
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
            .navigationTitle("Settings")
            .helmScreenBackground()
        }
        .helmTheme()
    }
}

#Preview {
    SettingsView()
}
