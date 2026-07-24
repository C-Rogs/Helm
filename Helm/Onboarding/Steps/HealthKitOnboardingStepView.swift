import DesignSystem
import HealthKitIngest
import SwiftUI

struct HealthKitOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 2
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onSkip: () -> Void = {}

    @State private var presence: [HealthKitDataPresence] = []
    @State private var status = HealthKitIngestStatus.idle
    @State private var isConnecting = false
    @State private var isChecking = false
    @State private var errorMessage: String?

    private let presenceChecker = HealthKitDataPresenceChecker()

    private var isConnected: Bool {
        status.connectionState == .connected
    }

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
                if isConnected {
                    connectedStatusSection
                } else {
                    Button(isConnecting ? "Connecting…" : "Connect Apple Health") {
                        Task { await connectHealth() }
                    }
                    .buttonStyle(.helmPrimary)
                    .disabled(isConnecting)
                }

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
        .task { await refreshAll() }
    }

    private var connectedStatusSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(HelmColor.ready)
                Text("Connected to Apple Health")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.fg)
            }

            if let lastSync = status.lastSyncFinishedAt {
                Text("Last sync \(lastSync.formatted(date: .abbreviated, time: .shortened))")
                    .font(HelmTypography.caption)
                    .foregroundStyle(HelmColor.fgSecondary)
            }

            Button(isConnecting ? "Refreshing…" : "Refresh data") {
                Task { await refreshData() }
            }
            .buttonStyle(.helmSecondary)
            .disabled(isConnecting)
        }
        .padding(HelmSpacing.md)
        .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
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

        await refreshAll()
    }

    private func refreshData() async {
        isConnecting = true
        defer { isConnecting = false }

        let outcome = await HealthKitBootstrap.healthKitIngest.syncNow()
        await ReadinessBootstrap.readinessService.recomputeAfterIngest(
            affectedFamilies: outcome.affectedFamilies
        )
        HapticEngine.shared.play(.selection)
        await refreshAll()
    }

    private func refreshAll() async {
        status = await HealthKitBootstrap.healthKitIngest.currentStatus()
        isChecking = true
        defer { isChecking = false }
        presence = await presenceChecker.checkAllKinds()
    }
}

#Preview {
    HealthKitOnboardingStepView()
        .helmTheme()
}
