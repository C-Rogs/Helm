import Diagnostics
import SwiftUI

struct SettingsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Diagnostics") {
                    DiagnosticsView(environment: ExportEnvironmentFactory.current())
                }
            }
            .navigationTitle("Settings")
        }
    }
}

#Preview {
    SettingsView()
}
