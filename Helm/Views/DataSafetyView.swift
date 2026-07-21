import Diagnostics
import Persistence
import SwiftUI

struct DataSafetyView: View {
    @State private var shareItem: ExportShareItem?
    @State private var isExporting = false
    @State private var exportErrorMessage: String?

    private let store: PersistenceStore
    private let logExportService: LogExportService
    private let environment: ExportEnvironment

    init(
        store: PersistenceStore = PersistenceBootstrap.persistenceStore,
        logExportService: LogExportService = LogExportService(),
        environment: ExportEnvironment = ExportEnvironmentFactory.current(
            schemaVersion: PersistenceBootstrap.schemaVersion
        )
    ) {
        self.store = store
        self.logExportService = logExportService
        self.environment = environment
    }

    var body: some View {
        List {
            Section {
                Button("Export Database") {
                    Task { await exportDatabase() }
                }
                .disabled(isExporting)

                Button("Export Diagnostics") {
                    Task { await exportDiagnostics() }
                }
                .disabled(isExporting)

                Button("Export Full Backup") {
                    Task { await exportFullBackup() }
                }
                .disabled(isExporting)
            } footer: {
                Text("Exports use the share sheet (AirDrop, Files, Mail). Nothing is uploaded automatically. See Docs/DATA-SAFETY.md for restore behaviour.")
            }

            Section("iCloud Backup") {
                LabeledContent("Policy", value: "Included")
                Text("Helm data in Application Support is included in your device iCloud backup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Data & Backup")
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

    private func exportDatabase() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let url = try await store.exportCheckpointedCopy()
            shareItem = ExportShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func exportDiagnostics() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let url = try await logExportService.exportBundle(environment: environment)
            shareItem = ExportShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
        }
    }

    private func exportFullBackup() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let databaseURL = try await store.exportCheckpointedCopy()
            let url = try await logExportService.exportFullBackup(
                databaseFileURL: databaseURL,
                environment: environment
            )
            shareItem = ExportShareItem(url: url)
        } catch {
            exportErrorMessage = error.localizedDescription
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
        DataSafetyView()
    }
}
