import Core
import HealthKitIngest
import Persistence
import SwiftUI

struct HealthKitStatusView: View {
    @State private var status = HealthKitIngestStatus.idle
    @State private var isSyncing = false
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

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Connection", value: status.connectionState.rawValue)
                LabeledContent("Observing", value: status.isObserving ? "Yes" : "No")
                if let lastSync = status.lastSyncFinishedAt {
                    LabeledContent("Last loaded") {
                        VStack(alignment: .trailing) {
                            Text(lastSync, style: .date)
                            Text(lastSync, style: .time)
                        }
                    }
                }
                LabeledContent("Last sample count", value: "\(status.lastSyncSampleCount)")
                LabeledContent("Last deleted count", value: "\(status.lastSyncDeletedCount)")
            }

            Section("Stored data") {
                LabeledContent("Days in database", value: "\(storedDayCount)")
                if let latestStoredDay {
                    LabeledContent("Latest day", value: latestStoredDay.formatted)
                }
            }

            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if !lastOutcome.affectedFamilies.isEmpty {
                Section("Last sync families") {
                    ForEach(
                        Array(lastOutcome.affectedFamilies).sorted(by: { $0.rawValue < $1.rawValue }),
                        id: \.self
                    ) { family in
                        Text(family.rawValue)
                    }
                }
            }

            Section {
                if status.connectionState != .connected {
                    Button("Request Health Access") {
                        Task { await requestAuthorization() }
                    }
                }
                Button(isSyncing ? "Syncing…" : "Sync Now") {
                    Task { await syncNow() }
                }
                .disabled(isSyncing)
            }

            Section("Backfill") {
                LabeledContent("Status", value: backfillStatusText)
                if isBackfilling {
                    ProgressView(value: backfillProgressFraction)
                }
                Button(isBackfilling ? "Backfilling…" : "Run 6-Month Backfill") {
                    Task { await runBackfill(force: true) }
                }
                .disabled(isBackfilling)
            }
        }
        .navigationTitle("HealthKit")
        .task { await hydrate() }
    }

    private var backfillStatusText: String {
        if backfillProgress.isComplete, backfillProgress.totalChunks > 0 {
            return "Complete (\(backfillProgress.completedChunks)/\(backfillProgress.totalChunks) chunks)"
        }
        if isBackfilling, backfillProgress.totalChunks > 0 {
            return "\(backfillProgress.completedChunks)/\(backfillProgress.totalChunks) chunks"
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
    }

    private func loadStoredDataSummary() async {
        do {
            let store = PersistenceBootstrap.persistenceStore
            let days = try await store.dailyMetrics.listDays()
            storedDayCount = days.count
            latestStoredDay = days.last
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshStatus() async {
        status = await HealthKitBootstrap.healthKitIngest.currentStatus()
        await loadStoredDataSummary()
    }

    private func requestAuthorization() async {
        errorMessage = nil
        do {
            try await HealthKitBootstrap.healthKitIngest.requestAuthorization()
            await HealthKitBootstrap.healthKitIngest.startObserving()
            lastOutcome = await HealthKitBootstrap.healthKitIngest.syncNow()
            await refreshStatus()
            await runBackfill(force: false)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncNow() async {
        isSyncing = true
        defer { isSyncing = false }
        lastOutcome = await HealthKitBootstrap.healthKitIngest.syncNow()
        await ReadinessBootstrap.readinessService.recomputeAfterIngest(
            affectedFamilies: lastOutcome.affectedFamilies
        )
        await refreshStatus()
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
    }
}
