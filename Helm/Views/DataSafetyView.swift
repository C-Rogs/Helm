import DesignSystem
import Diagnostics
import Persistence
import SwiftUI
import UniformTypeIdentifiers

struct DataSafetyView: View {
    /// SwiftUI honours only the last `fileImporter` attached to a view, so both
    /// import paths share one importer keyed by this.
    private enum ImportTarget {
        case hevyCSV
        case trainingJSON

        var contentTypes: [UTType] {
            switch self {
            case .hevyCSV: [.commaSeparatedText, .plainText, .text]
            case .trainingJSON: [.json]
            }
        }
    }

    private enum ActiveSheet: Identifiable {
        case share(URL)
        case hevyPreview
        case trainingPreview

        var id: String {
            switch self {
            case let .share(url): "share-\(url.absoluteString)"
            case .hevyPreview: "hevy-preview"
            case .trainingPreview: "training-preview"
            }
        }
    }

    @State private var shareItem: ExportShareItem?
    @State private var isExporting = false
    @State private var exportErrorMessage: String?
    @State private var importTarget: ImportTarget?
    @State private var isImporting = false
    @State private var transferController: TrainingHistoryTransferController

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
        _transferController = State(initialValue: TrainingHistoryTransferController(persistence: store))
    }

    var body: some View {
        List {
            Section {
                Button("Export Training History") {
                    Task { await exportTrainingHistory() }
                }
                .disabled(isExporting)
                .helmListRowChrome()

                Button("Import Training History") {
                    beginImport(.trainingJSON)
                }
                .helmListRowChrome()

                Button("Import Hevy CSV") {
                    beginImport(.hevyCSV)
                }
                .helmListRowChrome()
            } header: {
                Text("Training history")
            } footer: {
                Text("Training History JSON is about 90 days of sessions, sets, and aliases: small enough for Files or AirDrop. Hevy CSV import clips to the last 90 days and maps exercise names before writing completed history.")
                    .helmType(.body, color: HelmColor.fgMuted)
            }

            if let status = transferController.statusMessage {
                Section {
                    Text(status)
                        .helmType(.body, color: HelmColor.fgSecondary)
                        .helmListRowChrome()
                }
            }

            Section {
                Button("Export Database") {
                    Task { await exportDatabase() }
                }
                .disabled(isExporting)
                .helmListRowChrome()

                Button("Export Diagnostics") {
                    Task { await exportDiagnostics() }
                }
                .disabled(isExporting)
                .helmListRowChrome()

                Button("Export Full Backup") {
                    Task { await exportFullBackup() }
                }
                .disabled(isExporting)
                .helmListRowChrome()
            } header: {
                Text("Full backup")
            } footer: {
                Text("Full database exports are large. Prefer Training History JSON for day-to-day wipe recovery. Share sheet only; nothing uploads automatically.")
                    .helmType(.body, color: HelmColor.fgMuted)
            }

            Section {
                HelmStatusRow(label: "Policy", value: "Excluded")
                    .helmListRowChrome()
                Text("Helm data in Application Support is excluded from iCloud device backup. HealthKit re-backfills after reinstall; use Training History JSON or a manual database export for Helm-logged workouts.")
                    .helmType(.body, color: HelmColor.fgMuted)
                    .helmListRowChrome()
            } header: {
                Text("iCloud Backup")
            }
        }
        .helmSettingsListChrome()
        .navigationTitle("Data & Backup")
        .sheet(item: activeSheet) { sheet in
            switch sheet {
            case let .share(url):
                ShareSheet(items: [url])
            case .hevyPreview:
                HevyCSVImportPreviewView(controller: transferController)
            case .trainingPreview:
                TrainingHistoryImportPreviewView(controller: transferController)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: importTarget?.contentTypes ?? [.data],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                switch importTarget {
                case .hevyCSV: transferController.loadHevyCSV(from: url)
                case .trainingJSON: transferController.loadTrainingHistory(from: url)
                case nil: break
                }
            case let .failure(error):
                transferController.errorMessage = error.localizedDescription
            }
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
        .alert(
            "Import issue",
            isPresented: Binding(
                get: {
                    transferController.errorMessage != nil
                        && !transferController.isShowingHevyPreview
                        && !transferController.isShowingTrainingImportPreview
                },
                set: { if !$0 { transferController.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transferController.errorMessage ?? "")
        }
    }

    private var activeSheet: Binding<ActiveSheet?> {
        Binding(
            get: {
                if let shareItem { return .share(shareItem.url) }
                if transferController.isShowingHevyPreview { return .hevyPreview }
                if transferController.isShowingTrainingImportPreview { return .trainingPreview }
                return nil
            },
            set: { newValue in
                guard newValue == nil else { return }
                shareItem = nil
                transferController.isShowingHevyPreview = false
                transferController.isShowingTrainingImportPreview = false
            }
        )
    }

    private func beginImport(_ target: ImportTarget) {
        transferController.errorMessage = nil
        importTarget = target
        isImporting = true
    }

    private func exportDatabase() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let url = try await store.exportCheckpointedCopy()
            shareItem = ExportShareItem(url: url)
            HapticEngine.shared.play(.selection)
        } catch {
            exportErrorMessage = error.localizedDescription
            HapticEngine.shared.play(.clampRejected)
        }
    }

    private func exportDiagnostics() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let url = try await logExportService.exportBundle(environment: environment)
            shareItem = ExportShareItem(url: url)
            HapticEngine.shared.play(.selection)
        } catch {
            exportErrorMessage = error.localizedDescription
            HapticEngine.shared.play(.clampRejected)
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
            HapticEngine.shared.play(.selection)
        } catch {
            exportErrorMessage = error.localizedDescription
            HapticEngine.shared.play(.clampRejected)
        }
    }

    private func exportTrainingHistory() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let url = try transferController.exportTrainingHistory()
            shareItem = ExportShareItem(url: url)
            HapticEngine.shared.play(.selection)
        } catch {
            exportErrorMessage = error.localizedDescription
            HapticEngine.shared.play(.clampRejected)
        }
    }
}

struct TrainingHistoryImportPreviewView: View {
    @Bindable var controller: TrainingHistoryTransferController

    private var pending: TrainingHistoryExport? {
        controller.pendingTrainingImport
    }

    private var setCount: Int {
        pending?.sessions.reduce(0) { $0 + $1.exercises.reduce(0) { $0 + $1.sets.count } } ?? 0
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if let pending {
                        HelmStatusRow(label: "Sessions", value: "\(pending.sessions.count)")
                            .helmListRowChrome()
                        HelmStatusRow(label: "Sets", value: "\(setCount)")
                            .helmListRowChrome()
                        HelmStatusRow(label: "Lookback days", value: "\(pending.lookbackDays)")
                            .helmListRowChrome()
                        HelmStatusRow(label: "Custom exercises", value: "\(pending.customExercises.count)")
                            .helmListRowChrome()
                    }
                } header: {
                    Text("Ready to import")
                } footer: {
                    Text("Import writes completed workout history. Duplicate sessions are skipped.")
                        .helmType(.body, color: HelmColor.fgMuted)
                }

                if let errorMessage = controller.errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .helmType(.body, color: HelmColor.depleted)
                            .helmListRowChrome()
                    }
                }

                Section {
                    Button("Confirm import") {
                        controller.confirmTrainingHistoryImport()
                        HapticEngine.shared.play(.selection)
                    }
                    .disabled(pending == nil)
                    .helmListRowChrome()

                    Button("Cancel", role: .cancel) {
                        controller.cancelTrainingHistoryImport()
                    }
                    .helmListRowChrome()
                }
            }
            .helmSettingsListChrome()
            .navigationTitle("Import Training History")
            .navigationBarTitleDisplayMode(.inline)
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
    .helmTheme()
}
