import Core
import DesignSystem
import SwiftUI

struct MorningBriefAutomationGuideView: View {
    var body: some View {
        List {
            Section {
                Text("Helm can generate your morning brief from Shortcuts without opening the app.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
                Text("If your phone is still locked, HealthKit data is unavailable. Open Helm and your brief will generate on the Dashboard.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Shortcuts setup") {
                Label("Create a Personal Automation", systemImage: "1.circle")
                Label("Trigger when your alarm is dismissed or when you unlock your phone", systemImage: "2.circle")
                Label("Add the Generate Morning Brief action from Helm", systemImage: "3.circle")
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
