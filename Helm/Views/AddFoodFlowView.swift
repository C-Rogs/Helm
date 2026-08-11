import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct AddFoodFlowView: View {
    @Bindable var controller: ManualFoodLogController
    let entryMode: AddFoodEntryMode

    @State private var selectedProduct: ResolvedFoodProduct?
    @State private var pendingBarcode: String?
    @State private var barcodePhase: BarcodeScanPhase = .scanning
    @State private var pendingQueueBucket: MealBucket
    @Environment(\.dismiss) private var dismiss

    init(controller: ManualFoodLogController, entryMode: AddFoodEntryMode) {
        self.controller = controller
        self.entryMode = entryMode
        _pendingQueueBucket = State(initialValue: controller.preferredBucket)
    }

    private enum BarcodeScanPhase: Equatable {
        case scanning
        case resolving
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let selectedProduct {
                    FoodPortionStepView(
                        product: selectedProduct,
                        defaults: controller.portionDefaults(for: selectedProduct),
                        isSaving: controller.isBusy,
                        initialBucket: controller.preferredBucket,
                        onLog: { grams, servingLabel, bucket in
                            Task {
                                await controller.logFood(
                                    product: selectedProduct,
                                    grams: grams,
                                    servingLabel: servingLabel,
                                    bucket: bucket,
                                    source: entryMode == .barcode ? .barcode : .manual
                                )
                            }
                        },
                        onCancel: {
                            self.selectedProduct = nil
                        }
                    )
                } else {
                    switch entryMode {
                    case .search:
                        FoodSearchView(
                            controller: controller,
                            isOnline: controller.isOnline,
                            onSelect: { product in
                                handleProductSelection(product)
                            }
                        )
                    case .barcode:
                        barcodeStep
                    case .quickAdd:
                        QuickAddFoodView(controller: controller)
                    case .alcohol:
                        AlcoholLogView(controller: controller)
                    }
                }
            }
            .toolbar {
                if selectedProduct == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            controller.cancel()
                        }
                    }
                }
            }
        }
        .task {
            await controller.refreshConnectivity()
        }
        .onChange(of: controller.phase) { oldPhase, newPhase in
            if case .saving = oldPhase, case .flow(.search) = newPhase {
                selectedProduct = nil
            }
            if case .idle = newPhase {
                dismiss()
            }
        }
        .sheet(isPresented: Binding(
            get: { pendingBarcode != nil },
            set: { isPresented in
                if !isPresented {
                    pendingBarcode = nil
                    barcodePhase = .scanning
                }
            }
        )) {
            if let barcode = pendingBarcode {
                OfflineBarcodeQueueSheet(
                    barcode: barcode,
                    bucket: $pendingQueueBucket,
                    onSave: {
                        Task {
                            await controller.queueOfflineBarcode(
                                barcode: barcode,
                                bucket: pendingQueueBucket
                            )
                            pendingBarcode = nil
                            barcodePhase = .scanning
                        }
                    },
                    onCancel: {
                        pendingBarcode = nil
                        barcodePhase = .scanning
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var barcodeStep: some View {
        switch barcodePhase {
        case .scanning:
            BarcodeScannerView(
                onBarcode: { barcode in
                    resolveBarcode(barcode)
                },
                onCancel: {
                    controller.cancel()
                }
            )
        case .resolving:
            VStack(spacing: HelmSpacing.md) {
                ProgressView()
                Text("Looking up product…")
                    .helmType(.body, color: HelmColor.fgMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .helmScreenBackground()
        case let .failed(message):
            VStack(spacing: HelmSpacing.lg) {
                HelmErrorState(
                    title: "Barcode not found",
                    message: message,
                    onRetry: {
                        barcodePhase = .scanning
                    }
                )
                Button("Done") {
                    controller.cancel()
                }
                .buttonStyle(.helmSecondary)
            }
            .padding(HelmSpacing.md)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .helmScreenBackground()
        }
    }

    private func handleProductSelection(_ product: ResolvedFoodProduct) {
        if controller.shouldSkipPortion(for: product) {
            let defaults = controller.portionDefaults(for: product)
            Task {
                await controller.logFood(
                    product: product,
                    grams: defaults.grams,
                    servingLabel: defaults.servingLabel,
                    bucket: controller.preferredBucket,
                    source: entryMode == .barcode ? .barcode : .manual
                )
            }
        } else {
            selectedProduct = product
        }
    }

    private func resolveBarcode(_ barcode: String) {
        barcodePhase = .resolving
        Task { @MainActor in
            do {
                let product = try await controller.resolveBarcode(barcode)
                handleProductSelection(product)
                barcodePhase = .scanning
            } catch FoodResolverError.offline {
                pendingBarcode = barcode
                barcodePhase = .scanning
            } catch {
                barcodePhase = .failed(lookupMessage(for: error))
            }
        }
    }

    private func lookupMessage(for error: Error) -> String {
        switch error {
        case FoodResolverError.offline:
            "Branded lookup needs a network connection."
        case FoodResolverError.notFound:
            "No product found for that barcode."
        case OpenFoodFactsError.productNotFound:
            "No product found for that barcode."
        default:
            "Could not look up that barcode. Tap Scan again to try another product."
        }
    }
}

#Preview("Add food search flow") {
    AddFoodFlowView(
        controller: ManualFoodLogController.previewController(online: true),
        entryMode: .search
    )
    .helmTheme()
}

#Preview("Add food barcode flow") {
    AddFoodFlowView(
        controller: ManualFoodLogController.previewController(online: true),
        entryMode: .barcode
    )
    .helmTheme()
}
