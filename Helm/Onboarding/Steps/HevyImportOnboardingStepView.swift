import DesignSystem
import Persistence
import SwiftUI
import UniformTypeIdentifiers

struct HevyImportOnboardingStepView: View {
    var showsFlowControls: Bool = true
    var stepIndex: Int = 6
    var totalSteps: Int = OnboardingStep.allCases.count
    var onContinue: () -> Void = {}
    var onBack: (() -> Void)? = nil
    var onSkip: () -> Void = {}

    @State private var transferController: TrainingHistoryTransferController
    @State private var isPickingFile = false

    init(
        showsFlowControls: Bool = true,
        stepIndex: Int = 6,
        totalSteps: Int = OnboardingStep.allCases.count,
        onContinue: @escaping () -> Void = {},
        onBack: (() -> Void)? = nil,
        onSkip: @escaping () -> Void = {},
        persistence: PersistenceStore = PersistenceBootstrap.persistenceStore
    ) {
        self.showsFlowControls = showsFlowControls
        self.stepIndex = stepIndex
        self.totalSteps = totalSteps
        self.onContinue = onContinue
        self.onBack = onBack
        self.onSkip = onSkip
        _transferController = State(initialValue: TrainingHistoryTransferController(persistence: persistence))
    }

    private var didImport: Bool {
        transferController.lastHevyImportResult != nil
    }

    var body: some View {
        OnboardingStepChrome(
            step: .hevyImport,
            stepIndex: stepIndex,
            totalSteps: totalSteps,
            showsFlowControls: showsFlowControls,
            primaryTitle: primaryTitle,
            isPrimaryLoading: transferController.isParsingHevyCSV,
            skipTitle: showsFlowControls && !didImport ? "Skip for now" : nil,
            onPrimary: {
                if didImport {
                    onContinue()
                } else {
                    beginPick()
                }
            },
            onBack: onBack,
            onSkip: onSkip
        ) {
            VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                Text("Export workouts as CSV from Hevy, then pick that file. Signal keeps the last 90 days and maps exercise names before writing completed history.")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.fgSecondary)
                Text("You can also import later from Settings, Data and Backup.")
                    .font(HelmTypography.body)
                    .foregroundStyle(HelmColor.fgMuted)
                if let status = transferController.statusMessage {
                    Text(status)
                        .font(HelmTypography.body)
                        .foregroundStyle(HelmColor.fg)
                }
            }
            .padding(HelmSpacing.md)
            .background(HelmColor.surface, in: RoundedRectangle(cornerRadius: HelmRadius.md))
        }
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

    private var primaryTitle: String {
        if transferController.isParsingHevyCSV { return "Reading CSV" }
        if didImport { return "Continue" }
        return "Choose Hevy CSV"
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
    HevyImportOnboardingStepView()
        .helmTheme()
}
