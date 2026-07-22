import HealthKitIngest
import SwiftUI

struct HealthKitStatusView: View {
    @State private var status = HealthKitIngestStatus.idle
    @State private var isSyncing = false
    @State private var lastOutcome = HealthKitIngestOutcome.empty
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Status") {
                LabeledContent("Observing", value: status.isObserving ? "Yes" : "No")
                LabeledContent("Authorization requested", value: status.authorizationRequested ? "Yes" : "No")
                if let lastSync = status.lastSyncFinishedAt {
                    LabeledContent("Last sync") {
                        Text(lastSync, style: .relative)
                    }
                }
                LabeledContent("Last sample count", value: "\(status.lastSyncSampleCount)")
                LabeledContent("Last deleted count", value: "\(status.lastSyncDeletedCount)")
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
                Button("Request Health Access") {
                    Task { await requestAuthorization() }
                }
                Button(isSyncing ? "Syncing…" : "Sync Now") {
                    Task { await syncNow() }
                }
                .disabled(isSyncing)
            }
        }
        .navigationTitle("HealthKit")
        .task { await refreshStatus() }
    }

    private func refreshStatus() async {
        status = await HealthKitBootstrap.healthKitIngest.currentStatus()
    }

    private func requestAuthorization() async {
        errorMessage = nil
        do {
            try await HealthKitBootstrap.healthKitIngest.requestAuthorization()
            await HealthKitBootstrap.healthKitIngest.startObserving()
            lastOutcome = await HealthKitBootstrap.healthKitIngest.syncNow()
            await refreshStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func syncNow() async {
        isSyncing = true
        defer { isSyncing = false }
        lastOutcome = await HealthKitBootstrap.healthKitIngest.syncNow()
        await refreshStatus()
    }
}
