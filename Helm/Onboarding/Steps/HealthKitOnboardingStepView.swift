import DesignSystem
import HealthKitIngest
import SwiftUI

struct HealthKitOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 1
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onSkip: () -> Void = {}

    @State private var presence: [HealthKitDataPresence] = []
    @State private var isConnecting = false
    @State private var isChecking = false
    @State private var errorMessage: String?

    private let presenceChecker = HealthKitDataPresenceChecker()

    var body: some View {
        OnboardingStepChrome(
            step: .healthKit,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            onPrimary: onContinue,
            onSkip: onSkip
        ) {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                Button(isConnecting ? "Connecting…" : "Connect Apple Health") {
                    Task { await connectHealth() }
                }
                .buttonStyle(.helmPrimary)
                .disabled(isConnecting)

                if isChecking {
                    ProgressView("Checking data…")
                }

                if !presence.isEmpty {
                    presenceSection
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(HelmTypography.caption)
                        .foregroundStyle(HelmColor.depleted)
                }
            }
        }
        .task { await refreshPresence() }
    }

    private var presenceSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            Text("Data found in Health")
                .font(HelmTypography.headline)
                .foregroundStyle(HelmColor.fg)

            ForEach(groupedFamilies, id: \.family) { group in
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    Text(group.title)
                        .font(HelmTypography.monoTag)
                        .foregroundStyle(HelmColor.fgMuted)
                        .textCase(.uppercase)

                    ForEach(group.items, id: \.kind) { item in
                        HStack {
                            Text(item.kind.displayName)
                                .font(HelmTypography.body)
                                .foregroundStyle(HelmColor.fgSecondary)
                            Spacer()
                            Image(systemName: item.hasData ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(item.hasData ? HelmColor.ready : HelmColor.fgMuted)
                        }
                    }
                }
            }

            Text("Helm checks for samples, not permission grants. Denied reads look empty here.")
                .font(HelmTypography.caption)
                .foregroundStyle(HelmColor.fgMuted)
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
    }

    private var groupedFamilies: [(family: HealthKitMetricFamily, title: String, items: [HealthKitDataPresence])] {
        let families = HealthKitMetricFamily.allCases
        return families.compactMap { family in
            let items = presence.filter { $0.kind.metricFamily == family }
            guard !items.isEmpty else { return nil }
            return (family, familyTitle(family), items)
        }
    }

    private func familyTitle(_ family: HealthKitMetricFamily) -> String {
        switch family {
        case .vitals: "Vitals"
        case .activity: "Activity"
        case .nutrition: "Nutrition"
        case .bodyComposition: "Body composition"
        case .sleep: "Sleep"
        case .workouts: "Workouts"
        }
    }

    private func connectHealth() async {
        isConnecting = true
        errorMessage = nil
        defer { isConnecting = false }

        do {
            try await HealthKitBootstrap.healthKitIngest.requestAuthorization()
            await HealthKitBootstrap.healthKitIngest.startObserving()
            let outcome = await HealthKitBootstrap.healthKitIngest.syncNow()
            await ReadinessBootstrap.readinessService.recomputeAfterIngest(
                affectedFamilies: outcome.affectedFamilies
            )
            HapticEngine.shared.play(.selection)
        } catch {
            errorMessage = error.localizedDescription
            HapticEngine.shared.play(.clampRejected)
        }

        await refreshPresence()
    }

    private func refreshPresence() async {
        isChecking = true
        defer { isChecking = false }
        presence = await presenceChecker.checkAllKinds()
    }
}

#Preview {
    HealthKitOnboardingStepView()
        .helmTheme()
}
