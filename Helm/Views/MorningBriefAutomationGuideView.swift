import DesignSystem
import SwiftUI

struct MorningBriefAutomationGuideView: View {
    var body: some View {
        List {
            Section {
                Text("Helm will appear in Shortcuts after the automation feature ships in a future update.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
                Text("For now, open Helm each morning for your brief on the Dashboard.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Coming soon") {
                Label("Create a Personal Automation", systemImage: "1.circle")
                Label("Trigger when alarm is dismissed or phone is unlocked", systemImage: "2.circle")
                Label("Run Helm morning brief action", systemImage: "3.circle")
            }

            Section {
                Button("Preview Shortcuts app") {
                    guard let url = URL(string: "shortcuts://") else { return }
                    UIApplication.shared.open(url)
                    HapticEngine.shared.play(.selection)
                }
            }
        }
        .navigationTitle("Morning Brief Automation")
        .helmScreenBackground()
    }
}
