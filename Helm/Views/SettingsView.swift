import Diagnostics
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("HealthKit") {
                    HealthKitStatusView()
                }
                NavigationLink("Data & Backup") {
                    DataSafetyView()
                }
                NavigationLink("Diagnostics") {
                    DiagnosticsView(environment: ExportEnvironmentFactory.current(
                        schemaVersion: PersistenceBootstrap.schemaVersion
                    ))
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
