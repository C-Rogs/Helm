import Core
import DesignSystem
import HealthKitIngest
import Persistence
import SwiftUI

/// Unified Apple Health settings: auth, sync, backfill, and presence.
struct AppleHealthSettingsView: View {
    @State private var status = HealthKitIngestStatus.idle
    @State private var presence: [HealthKitDataPresence] = []
    @State private var isSyncing = false
    @State private var isConnecting = false
    @State private var isChecking = false
    @State private var lastOutcome = HealthKitIngestOutcome.empty
    @State private var errorMessage: String?
    @State private var isBackfilling = false
    @State private var backfillProgress = BackfillProgress(
        completedChunks: 0,
        totalChunks: 0,
        samplesIngestedThisRun: 0,
        isComplete: false
    )
    @State private var storedDayCount = 0
    @State private var latestStoredDay: HelmDay?
    @State private var latestBodyFatText = "None stored"
    @State private var bodyFatTrace = BodyFatQueryTrace.empty
    @State private var showsAdvancedDetail = false

    private let presenceChecker = HealthKitDataPresenceChecker()

    private var isConnected: Bool {
        status.connectionState == .connected
    }

    var body: some View {
        List {
            Section {
                Text(RestingHeartRateDisplay.settingsHealthExplanation)
                    .helmType(.body, color: HelmColor.fgMuted)
                    .helmListRowChrome()
            }

            Section("Status") {
                HelmStatusRow(
                    label: "Connection",
                    value: status.connectionState.rawValue,
                    valueColor: isConnected ? HelmColor.ready : HelmColor.fgMuted
                )
                .helmListRowChrome()

                if let lastSync = status.lastSyncFinishedAt {
                    LabeledContent("Last sync") {
                        VStack(alignment: .trailing, spacing: HelmSpacing.xxs) {
                            Text(lastSync, style: .date)
                            Text(lastSync, style: .time)
                        }
                        .helmType(.body, color: HelmColor.fgSecondary)
                    }
                    .helmListRowChrome()
                }

                HelmStatusRow(
                    label: "Observing",
                    value: status.isObserving ? "Yes" : "No",
                    valueColor: status.isObserving ? HelmColor.ready : HelmColor.fgMuted
                )
                .helmListRowChrome()
            }

            if !presence.isEmpty {
                Section("Data in Health") {
                    ForEach(groupedFamilies, id: \.family) { group in
                        ForEach(group.items, id: \.kind) { item in
                            HStack {
                                Text(item.kind.displayName)
                                    .helmType(.body)
                                Spacer()
                                Image(systemName: item.hasData ? "checkmark.circle.fill" : "minus.circle")
                                    .foregroundStyle(item.hasData ? HelmColor.ready : HelmColor.fgMuted)
                                    .accessibilityLabel(item.hasData ? "Present" : "Missing")
                            }
                            .helmListRowChrome()
                        }
                    }
                    Text("Signal checks for samples, not permission grants. Denied reads look empty here. A checkmark means at least one sample exists, not that today synced.")
                        .helmType(.body, color: HelmColor.fgMuted)
                        .helmListRowChrome()
                }
            }

            if let errorMessage {
                Section {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .helmType(.body, color: HelmColor.depleted)
                        .helmListRowChrome()
                }
            }

            Section {
                if !isConnected {
                    Button(isConnecting ? "Connecting…" : "Connect Apple Health") {
                        Task { await requestAuthorization() }
                    }
                    .disabled(isConnecting)
                    .helmListRowChrome()
                }

                Button(isSyncing ? "Syncing…" : "Sync Now") {
                    Task { await syncNow() }
                }
                .disabled(isSyncing || isConnecting)
                .helmListRowChrome()
            }

            Section("Import history") {
                HelmStatusRow(label: "Backfill", value: backfillStatusText)
                    .helmListRowChrome()
                if isBackfilling {
                    ProgressView(value: backfillProgressFraction)
                        .helmListRowChrome()
                }
                Button(isBackfilling ? "Backfilling…" : "Run 6-month backfill") {
                    Task { await runBackfill(force: true) }
                }
                .disabled(isBackfilling)
                .helmListRowChrome()
                Text("Loads about six months of Health samples into Signal. Safe to re-run; already-imported chunks are skipped.")
                    .helmType(.body, color: HelmColor.fgMuted)
                    .helmListRowChrome()
            }

            Section {
                Toggle("Show advanced detail", isOn: $showsAdvancedDetail)
                    .helmListRowChrome()
            }

            if showsAdvancedDetail {
                Section("Stored data") {
                    HelmStatusRow(label: "Days in database", value: "\(storedDayCount)")
                        .helmListRowChrome()
                    if let latestStoredDay {
                        HelmStatusRow(label: "Latest day", value: latestStoredDay.formatted)
                            .helmListRowChrome()
                    }
                    HelmStatusRow(label: "Latest body fat", value: latestBodyFatText)
                        .helmListRowChrome()
                    HelmStatusRow(label: "Last sample count", value: "\(status.lastSyncSampleCount)")
                        .helmListRowChrome()
                    HelmStatusRow(label: "Last deleted count", value: "\(status.lastSyncDeletedCount)")
                        .helmListRowChrome()
                }

                Section("Body fat probe") {
                    HelmStatusRow(
                        label: "HK samples",
                        value: "\(bodyFatTrace.hkSampleCount)"
                    )
                    .helmListRowChrome()
                    HelmStatusRow(
                        label: "Newest HK day",
                        value: bodyFatTrace.newestHkDay ?? "None"
                    )
                    .helmListRowChrome()
                    HelmStatusRow(
                        label: "Newest stored day",
                        value: bodyFatTrace.storedDay ?? "None"
                    )
                    .helmListRowChrome()
                    HelmStatusRow(label: "Lag", value: bodyFatTrace.lag)
                        .helmListRowChrome()
                    HelmStatusRow(
                        label: "Would ingest",
                        value: "\(bodyFatTrace.keptCount)"
                    )
                    .helmListRowChrome()
                    if bodyFatTrace.skippedOwnSource > 0 {
                        HelmStatusRow(
                            label: "Skipped own source",
                            value: "\(bodyFatTrace.skippedOwnSource)"
                        )
                        .helmListRowChrome()
                    }
                    if bodyFatTrace.skippedIncompatibleUnit > 0 {
                        HelmStatusRow(
                            label: "Skipped unit",
                            value: "\(bodyFatTrace.skippedIncompatibleUnit)"
                        )
                        .helmListRowChrome()
                    }
                    if bodyFatTrace.skippedOutOfRange > 0 {
                        HelmStatusRow(
                            label: "Skipped out of range",
                            value: "\(bodyFatTrace.skippedOutOfRange)"
                        )
                        .helmListRowChrome()
                    }
                    HelmStatusRow(label: "Sources", value: bodyFatTrace.sources)
                        .helmListRowChrome()
                    if let queryError = bodyFatTrace.queryError {
                        HelmStatusRow(label: "Query error", value: queryError)
                            .helmListRowChrome()
                    }
                    if let overlayError = bodyFatTrace.overlayError {
                        HelmStatusRow(label: "Overlay error", value: overlayError)
                            .helmListRowChrome()
                    }
                    Text("Newest HK day is the latest Body Fat Percentage sample HealthKit gave Signal. Health can mark the type present from an old reading. If a scale weigh-in is missing, check that the scale wrote that type to Health before assuming a Signal bug. Same probe lands in Settings → Export Diagnostics.")
                        .helmType(.body, color: HelmColor.fgMuted)
                        .helmListRowChrome()
                }

                if !lastOutcome.affectedFamilies.isEmpty {
                    Section("Last sync families") {
                        ForEach(
                            Array(lastOutcome.affectedFamilies).sorted(by: { $0.rawValue < $1.rawValue }),
                            id: \.self
                        ) { family in
                            Text(family.rawValue)
                                .helmType(.monoTag, color: HelmColor.fgMuted)
                                .helmListRowChrome()
                        }
                    }
                }
            }
        }
        .helmSettingsListChrome()
        .navigationTitle("Apple Health")
        .task { await hydrate() }
    }

    private var groupedFamilies: [(family: HealthKitMetricFamily, title: String, items: [HealthKitDataPresence])] {
        HealthKitMetricFamily.allCases.compactMap { family in
            let items = presence.filter { $0.kind.metricFamily == family }
            guard !items.isEmpty else { return nil }
            return (family, family.rawValue, items)
        }
    }

    private var backfillStatusText: String {
        if backfillProgress.isComplete, backfillProgress.totalChunks > 0 {
            return "Complete (\(backfillProgress.completedChunks)/\(backfillProgress.totalChunks))"
        }
        if backfillProgress.totalChunks > 0 {
            return "\(backfillProgress.completedChunks)/\(backfillProgress.totalChunks) chunks"
        }
        return "Not started"
    }

    private var backfillProgressFraction: Double {
        guard backfillProgress.totalChunks > 0 else { return 0 }
        return Double(backfillProgress.completedChunks) / Double(backfillProgress.totalChunks)
    }

    private func hydrate() async {
        status = await HealthKitBootstrap.healthKitIngest.currentStatus()
        backfillProgress = await HealthKitBootstrap.backfillService.savedProgress()
        await loadStoredDataSummary()
        if isConnected {
            isChecking = true
            defer { isChecking = false }
            presence = await presenceChecker.checkAllKinds()
        }
    }

    private func loadStoredDataSummary() async {
        do {
            let store = PersistenceBootstrap.persistenceStore
            let days = try store.dailyMetrics.listDays()
            storedDayCount = days.count
            latestStoredDay = days.last
            let today = HelmDay.day(for: Date(), calendar: .current)
            if let fat = try store.bodyComposition.fetchLatestWithBodyFat(onOrBefore: today),
               let percent = fat.bodyFatPercentage {
                latestBodyFatText = String(format: "%.1f%% on %@", percent, fat.helmDay.formatted)
            } else {
                latestBodyFatText = "None stored"
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        _ = await HealthKitBootstrap.healthKitIngest.liveBodyFatSummary()
        bodyFatTrace = await HealthKitBootstrap.healthKitIngest.lastBodyFatQueryTrace()
    }

    private func requestAuthorization() async {
        errorMessage = nil
        isConnecting = true
        defer { isConnecting = false }
        do {
            try await HealthKitBootstrap.healthKitIngest.requestAuthorization()
            await HealthKitBootstrap.healthKitIngest.startObserving()
            lastOutcome = await HealthKitBootstrap.healthKitIngest.syncNow()
            await ReadinessBootstrap.readinessService.recomputeAfterIngest(
                affectedFamilies: lastOutcome.affectedFamilies
            )
            status = await HealthKitBootstrap.healthKitIngest.currentStatus()
            presence = await presenceChecker.checkAllKinds()
            await loadStoredDataSummary()
            await runBackfill(force: false)
            HapticEngine.shared.play(.selection)
        } catch {
            errorMessage = error.localizedDescription
            HapticEngine.shared.play(.clampRejected)
        }
    }

    private func syncNow() async {
        isSyncing = true
        defer { isSyncing = false }
        lastOutcome = await HealthKitBootstrap.healthKitIngest.syncNow()
        await ReadinessBootstrap.readinessService.recomputeAfterIngest(
            affectedFamilies: lastOutcome.affectedFamilies
        )
        status = await HealthKitBootstrap.healthKitIngest.currentStatus()
        presence = await presenceChecker.checkAllKinds()
        await loadStoredDataSummary()
        HapticEngine.shared.play(.selection)
    }

    private func runBackfill(force: Bool) async {
        isBackfilling = true
        defer { isBackfilling = false }

        let service = HealthKitBootstrap.backfillService
        if force {
            let window = BackfillWindow.sixMonths()
            try? await service.resetCursor(for: window)
            for await progress in await service.run(window: window) {
                backfillProgress = progress
            }
        } else {
            for await progress in await service.runDefaultIfNeeded() {
                backfillProgress = progress
            }
        }
        await ReadinessBootstrap.readinessService.refresh()
        await loadStoredDataSummary()
        HapticEngine.shared.play(.selection)
    }
}

/// Compatibility alias for older call sites and screenshots.
typealias HealthKitStatusView = AppleHealthSettingsView

#Preview("Apple Health") {
    NavigationStack {
        AppleHealthSettingsView()
    }
    .helmTheme()
}

#Preview("Apple Health accessibility") {
    NavigationStack {
        AppleHealthSettingsView()
    }
    .helmTheme()
    .dynamicTypeSize(.accessibility5)
}
