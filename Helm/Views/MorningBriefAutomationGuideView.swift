import Core
import DesignSystem
import SwiftUI

struct MorningBriefAutomationGuideView: View {
    var body: some View {
        List {
            Section {
                Text("Helm delivers three local notifications: your morning brief, a pre-workout prime before your usual session window, and a post-workout summary when you finish logging.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
                Text("Morning briefs need HealthKit data. If your phone is still locked, open Helm and the brief generates on the Dashboard.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Morning brief automation") {
                Label("Open Shortcuts and create a Personal Automation", systemImage: "1.circle")
                Label("Choose Alarm → Is Dismissed, or choose When I unlock my iPhone", systemImage: "2.circle")
                Label("Add Generate Morning Brief from Helm", systemImage: "3.circle")
                Label("Turn off Ask Before Running so it fires automatically", systemImage: "4.circle")
            }

            Section("Pre-workout prime") {
                Text("Helm schedules a pre-workout notification about 30 minutes before your typical session start, inferred from recent workout history. No Shortcuts setup needed.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Post-workout summary") {
                Text("When you finish a logged session in Train, Helm posts a local summary with set count, duration, and any PRs. No Shortcuts setup needed.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section("Threshold insights") {
                Text("When a readiness contributor crosses a baseline threshold, Helm surfaces it on the Dashboard only. No push notification. Optional haptics are in Settings.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Section {
                Button("Open Shortcuts") {
                    guard let url = URL(string: "shortcuts://") else { return }
                    UIApplication.shared.open(url)
                    HapticEngine.shared.play(.selection)
                }
            }
        }
        .navigationTitle("Proactive Notifications")
        .helmScreenBackground()
    }
}

#Preview {
    NavigationStack {
        MorningBriefAutomationGuideView()
    }
    .helmTheme()
}
