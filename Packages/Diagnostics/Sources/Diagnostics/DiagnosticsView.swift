import SwiftUI

public struct DiagnosticsView: View {
    @State private var entries: [LogEntry] = []
    @State private var shareItem: ExportShareItem?
    @State private var isExporting = false
    @State private var exportErrorMessage: String?

    private let log: DiagnosticsLog
    private let exportService: LogExportService
    private let environment: ExportEnvironment

    public init(
        log: DiagnosticsLog = .shared,
        exportService: LogExportService = LogExportService(),
        environment: ExportEnvironment
    ) {
        self.log = log
        self.exportService = exportService
        self.environment = environment
    }

    public var body: some View {
        List {
            if entries.isEmpty {
                ContentUnavailableView(
                    "No log entries",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("Structured diagnostics will appear here as the app runs.")
                )
            } else {
                ForEach(entries) { entry in
                    LogEntryRow(entry: entry)
                }
            }
        }
        .navigationTitle("Diagnostics")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Export") {
                    Task { await exportLogs() }
                }
                .disabled(isExporting)
            }
        }
        .refreshable {
            await reloadEntries()
        }
        .task {
            await reloadEntries()
        }
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
        }
        .alert(
            "Export failed",
            isPresented: Binding(
                get: { exportErrorMessage != nil },
                set: { if !$0 { exportErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportErrorMessage ?? "")
        }
    }

    private func reloadEntries() async {
        entries = await log.entriesNewestFirst()
    }

    private func exportLogs() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let url = try await exportService.exportBundle(environment: environment)
            shareItem = ExportShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.category)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text(entry.level.rawValue.uppercased())
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(levelColor)
            }
            Text(entry.message)
                .font(.body)
            if let context = entry.context, !context.isEmpty {
                Text(context.map { "\($0.key): \($0.value)" }.sorted().joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let errorType = entry.errorType {
                Text(errorType)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
            }
            Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private var levelColor: Color {
        switch entry.level {
        case .error: .red
        case .info: .blue
        case .debug: .secondary
        }
    }
}

private struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        DiagnosticsView(
            environment: ExportEnvironment(
                appVersion: "1.0.0",
                buildNumber: "1",
                deviceModel: "iPhone",
                osVersion: "26.0"
            )
        )
    }
}
