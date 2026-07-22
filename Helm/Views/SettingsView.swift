import Diagnostics
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
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
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
