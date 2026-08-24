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
    @Bindable private var cloudPreferences = CloudBackupPreferences.shared
    @Bindable private var cloudCoordinator = CloudBackupCoordinator.shared

    private static let relativeDate: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

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

    private func historySizeLabel(_ estimate: CloudBackupSizeEstimate) -> String {
        "\(estimate.historyByteCountFormatted) · \(estimate.historySessionCount) sessions on this device"
    }

    private func nutritionSizeLabel(_ estimate: CloudBackupSizeEstimate) -> String {
        let mealCount = estimate.nutritionMealCount ?? 0
        if cloudPreferences.nutritionSyncEnabled {
            return "\(estimate.nutritionByteCountFormatted) · \(mealCount) meals"
        }
        return "\(estimate.nutritionByteCountFormatted) if enabled · \(mealCount) meals"
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
                Toggle("Sync profile & engine config", isOn: $cloudPreferences.profileSyncEnabled)
                    .helmListRowChrome()

                Toggle("Include workout history (90 days)", isOn: $cloudPreferences.historySyncEnabled)
                    .disabled(!cloudPreferences.profileSyncEnabled)
                    .helmListRowChrome()

                Toggle("Include food log (30 days)", isOn: $cloudPreferences.nutritionSyncEnabled)
                    .disabled(!cloudPreferences.profileSyncEnabled)
                    .helmListRowChrome()

                if let estimate = cloudCoordinator.sizeEstimate {
                    HelmStatusRow(
                        label: "Profile size",
                        value: estimate.profileByteCountFormatted
                    )
                    .helmListRowChrome()
                    HelmStatusRow(
                        label: "History on device",
                        value: historySizeLabel(estimate)
                    )
                    .helmListRowChrome()
                    HelmStatusRow(
                        label: "History in iCloud",
                        value: cloudCoordinator.cloudHistoryStatusMessage ?? "Checking…"
                    )
                    .helmListRowChrome()
                    HelmStatusRow(
                        label: "Nutrition size",
                        value: nutritionSizeLabel(estimate)
                    )
                    .helmListRowChrome()
                }

                HelmStatusRow(
                    label: "iCloud Drive",
                    value: cloudCoordinator.isAvailable ? "Available" : "Unavailable"
                )
                .helmListRowChrome()

                if let lastPushed = cloudPreferences.lastPushedAt {
                    HelmStatusRow(
                        label: "Last backup",
                        value: Self.relativeDate.localizedString(for: lastPushed, relativeTo: Date())
                    )
                    .helmListRowChrome()
                }
                if let lastRestored = cloudPreferences.lastRestoredAt {
                    HelmStatusRow(
                        label: "Last restore",
                        value: Self.relativeDate.localizedString(for: lastRestored, relativeTo: Date())
                    )
                    .helmListRowChrome()
                }

                Button("Back Up Now") {
                    Task {
                        let ok = await cloudCoordinator.pushNow()
                        if ok { HapticEngine.shared.play(.selection) }
                        else { HapticEngine.shared.play(.clampRejected) }
                    }
                }
                .disabled(cloudCoordinator.isBusy || !cloudPreferences.profileSyncEnabled)
                .helmListRowChrome()

                if cloudCoordinator.isBusy {
                    HStack {
                        ProgressView()
                            .padding(.trailing, 8)
                        Text("Working...")
                            .helmType(.body, color: HelmColor.fgSecondary)
                    }
                    .helmListRowChrome()
                }

                Button("Restore from iCloud") {
                    Task {
                        let ok = await cloudCoordinator.restoreForced()
                        if ok { HapticEngine.shared.play(.selection) }
                        else { HapticEngine.shared.play(.clampRejected) }
                    }
                }
                .disabled(cloudCoordinator.isBusy || !cloudCoordinator.isAvailable)
                .helmListRowChrome()

                if let status = cloudCoordinator.statusMessage {
                    Text(status)
                        .helmType(.body, color: HelmColor.fgSecondary)
                        .helmListRowChrome()
                }
                if let error = cloudCoordinator.errorMessage {
                    Text(error)
                        .helmType(.body, color: HelmColor.depleted)
                        .helmListRowChrome()
                }
            } header: {
                Text("iCloud sync")
            } footer: {
                Text("Opt-in iCloud Drive backup of coach memory, body profile, training plan, and mesocycle state. Optional 90-day workout history restores PBs after delete/reinstall. History on device includes HealthKit cardio; iCloud history is Helm-logged workouts only. Optional 30-day food log includes recents, meal templates, and recent meals. HealthKit re-backfills health rows on reinstall.")
                    .helmType(.body, color: HelmColor.fgMuted)
            }
        }
        .helmSettingsListChrome()
        .navigationTitle("Data & Backup")
        .task {
            cloudCoordinator.refreshEstimate()
            await cloudCoordinator.refreshCloudStatus()
        }
        .onChange(of: cloudPreferences.profileSyncEnabled) { _, enabled in
            cloudCoordinator.refreshEstimate()
            if enabled {
                cloudCoordinator.schedulePush()
            }
        }
        .onChange(of: cloudPreferences.historySyncEnabled) { _, _ in
            cloudCoordinator.refreshEstimate()
            if cloudPreferences.profileSyncEnabled {
                cloudCoordinator.schedulePush()
            }
        }
        .onChange(of: cloudPreferences.nutritionSyncEnabled) { _, _ in
            cloudCoordinator.refreshEstimate()
            if cloudPreferences.profileSyncEnabled {
                cloudCoordinator.schedulePush()
            }
        }
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
