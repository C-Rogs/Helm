import DesignSystem
import SwiftUI

struct NotificationOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 2
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onSkip: () -> Void = {}

    @State private var status: NotificationAuthorizationStatus = .notDetermined
    @State private var isRequesting = false

    private let permissionService = NotificationPermissionService()

    var body: some View {
        OnboardingStepChrome(
            step: .notifications,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            onPrimary: onContinue,
            onSkip: onSkip
        ) {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                LabeledContent("Status") {
                    Text(statusLabel)
                        .foregroundStyle(HelmColor.fgSecondary)
                }
                .font(HelmTypography.body)

                Button(isRequesting ? "Requesting…" : "Enable Notifications") {
                    Task { await requestPermission() }
                }
                .buttonStyle(.helmPrimary)
                .disabled(isRequesting || status == .authorized)
            }
            .padding(HelmSpacing.md)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        }
        .task { await refreshStatus() }
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
}

#Preview {
    NotificationOnboardingStepView()
        .helmTheme()
}
