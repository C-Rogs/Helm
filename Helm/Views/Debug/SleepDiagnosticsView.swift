import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct SleepDiagnosticsView: View {
    @State private var snapshot: SleepDiagnosticsSnapshot?
    @State private var errorMessage: String?
    @State private var isLoading = false

    var body: some View {
        List {
            if let errorMessage {
                Section("Error") {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }

            if let snapshot {
                summarySection(
                    title: "HealthKit (Time Asleep)",
                    summary: snapshot.healthKitSummary
                )
                summarySection(
                    title: "Helm persisted",
                    summary: snapshot.persistedSummary
                )

                Section("Window") {
                    LabeledContent("Wake day", value: formattedDay(snapshot.wakeCalendarDay))
                    LabeledContent("Start", value: formattedTime(snapshot.windowStart))
                    LabeledContent("End", value: formattedTime(snapshot.windowEnd))
                }

                Section("HealthKit samples (\(snapshot.healthKitSamples.count))") {
                    if snapshot.healthKitSamples.isEmpty {
                        Text("No samples in window")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.healthKitSamples) { sample in
                            sampleRow(sample)
                        }
                    }
                }

                Section("Persisted intervals (\(snapshot.persistedRecords.count))") {
                    if snapshot.persistedRecords.isEmpty {
                        Text("No persisted intervals in window")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(snapshot.persistedRecords) { record in
                            persistedRow(record)
                        }
                    }
                }
            } else if isLoading {
                Section {
                    ProgressView("Loading sleep diagnostics…")
                }
            }
        }
        .navigationTitle("Sleep diagnostics")
        .refreshable { await reload() }
        .task { await reload() }
    }

    @ViewBuilder
    private func summarySection(title: String, summary: SleepNightSummary) -> some View {
        Section(title) {
            metricRow("Time asleep", hours: summary.asleepHours)
            metricRow("In bed", hours: summary.inBedHours)
            metricRow("Awake (WASO)", minutes: summary.awakeMinutes)
            metricRow("Deep", minutes: summary.deepMinutes)
            metricRow("REM", minutes: summary.remMinutes)
            if let efficiency = summary.efficiency {
                LabeledContent("Efficiency") {
                    Text("\(Int((efficiency * 100).rounded()))%")
                }
            }
        }
    }

    @ViewBuilder
    private func metricRow(_ label: String, hours: Double?) -> some View {
        if let hours {
            LabeledContent(label) {
                Text(SleepDurationFormatting.hoursAndMinutes(from: hours))
            }
        }
    }

    @ViewBuilder
    private func metricRow(_ label: String, minutes: Double?) -> some View {
        if let minutes {
            LabeledContent(label) {
                Text(SleepDurationFormatting.hoursAndMinutes(from: minutes / 60.0))
            }
        }
    }

    private func sampleRow(_ sample: SleepDiagnosticSample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sample.stage.displayName)
                .font(.headline)
            Text("\(formattedTime(sample.start)) – \(formattedTime(sample.end))")
                .font(.caption.monospaced())
            if let bundleID = sample.sourceBundleID {
                Text(bundleID)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func persistedRow(_ record: SleepRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(record.stage.displayName)
                .font(.headline)
            Text("\(formattedTime(record.start)) – \(formattedTime(record.end))")
                .font(.caption.monospaced())
            Text("helmDay \(record.helmDay.formatted)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            snapshot = try await SleepDiagnosticsService.loadLastNight(
                store: PersistenceBootstrap.persistenceStore
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func formattedDay(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    private func formattedTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

#Preview {
    NavigationStack {
        SleepDiagnosticsView()
    }
    .helmTheme()
}
