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

    private var isEnabled: Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

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
                if isEnabled {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(HelmColor.ready)
                        Text("Notifications enabled")
                            .font(HelmTypography.body)
                            .foregroundStyle(HelmColor.fg)
                    }
                    .padding(HelmSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
                } else if status == .denied {
                    VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                        Text("Notifications are off in Settings.")
                            .font(HelmTypography.body)
                            .foregroundStyle(HelmColor.fgSecondary)
                        Button("Open Settings") {
                            openSettings()
                        }
                        .buttonStyle(.helmPrimary)
                    }
                    .padding(HelmSpacing.md)
                    .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
                } else {
                    Button(isRequesting ? "Requesting…" : "Enable Notifications") {
                        Task { await requestPermission() }
                    }
                    .buttonStyle(.helmPrimary)
                    .disabled(isRequesting)
                    .padding(HelmSpacing.md)
                    .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
                }

                LabeledContent("Status") {
                    Text(statusLabel)
                        .foregroundStyle(HelmColor.fgSecondary)
                }
                .font(HelmTypography.body)
                .padding(.horizontal, HelmSpacing.md)
            }
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

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        HapticEngine.shared.play(.selection)
    }
}

#Preview {
    NotificationOnboardingStepView()
        .helmTheme()
}
