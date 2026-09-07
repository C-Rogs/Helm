import DesignSystem
import Persistence
import SwiftUI
import UniformTypeIdentifiers

/// Settings entry for Hevy CSV import (removed from required onboarding).
struct HevyImportSettingsView: View {
    @State private var transferController: TrainingHistoryTransferController
    @State private var isPickingFile = false

    init(persistence: PersistenceStore = PersistenceBootstrap.persistenceStore) {
        _transferController = State(initialValue: TrainingHistoryTransferController(persistence: persistence))
    }

    private var didImport: Bool {
        transferController.lastHevyImportResult != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    Text("Import Hevy CSV")
                        .font(HelmTypography.title)
                        .foregroundStyle(HelmColor.fg)

                    Text("Export workouts as CSV from Hevy, then pick that file. Signal keeps the last 180 days and maps exercise names before writing completed history.")
                        .font(HelmTypography.body)
                        .foregroundStyle(HelmColor.fgSecondary)
                }

                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    if let status = transferController.statusMessage {
                        Text(status)
                            .font(HelmTypography.body)
                            .foregroundStyle(HelmColor.fg)
                    } else if didImport {
                        Text("Import complete.")
                            .font(HelmTypography.body)
                            .foregroundStyle(HelmColor.ready)
                    } else {
                        Text("No file imported yet.")
                            .font(HelmTypography.body)
                            .foregroundStyle(HelmColor.fgMuted)
                    }
                }
                .padding(HelmSpacing.md)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))

                Button {
                    HapticEngine.shared.play(.selection)
                    beginPick()
                } label: {
                    if transferController.isParsingHevyCSV {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(HelmColor.buttonPrimaryForeground)
                            .accessibilityLabel("Reading CSV")
                    } else {
                        Text(didImport ? "Choose another CSV" : "Choose Hevy CSV")
                    }
                }
                .buttonStyle(.helmPrimary)
                .disabled(transferController.isParsingHevyCSV)
                .opacity(transferController.isParsingHevyCSV ? 0.65 : 1)
            }
            .padding(HelmSpacing.lg)
        }
        .helmScreenBackground()
        .navigationTitle("Import Hevy CSV")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: hevyPreviewPresented) {
            HevyCSVImportPreviewView(controller: transferController)
        }
        .fileImporter(
            isPresented: $isPickingFile,
            allowedContentTypes: [.commaSeparatedText, .plainText, .text],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case let .success(urls):
                guard let url = urls.first else { return }
                transferController.loadHevyCSV(from: url)
            case let .failure(error):
                transferController.errorMessage = error.localizedDescription
            }
        }
        .alert(
            "Import issue",
            isPresented: Binding(
                get: {
                    transferController.errorMessage != nil
                        && !transferController.isShowingHevyPreview
                },
                set: { if !$0 { transferController.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(transferController.errorMessage ?? "")
        }
    }

    private var hevyPreviewPresented: Binding<Bool> {
        Binding(
            get: { transferController.isShowingHevyPreview },
            set: { transferController.isShowingHevyPreview = $0 }
        )
    }

    private func beginPick() {
        transferController.errorMessage = nil
        isPickingFile = true
    }
}

#Preview {
    NavigationStack {
        HevyImportSettingsView()
    }
    .helmTheme()
}
