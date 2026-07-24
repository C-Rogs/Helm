import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct AddFoodFlowView: View {
    @Bindable var controller: ManualFoodLogController
    let entryMode: AddFoodEntryMode

    @State private var selectedProduct: ResolvedFoodProduct?
    @State private var lookupError: String?
    @State private var isResolvingBarcode = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let selectedProduct {
                    FoodPortionStepView(
                        product: selectedProduct,
                        defaults: controller.portionDefaults(for: selectedProduct),
                        isSaving: controller.isBusy,
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
                                selectedProduct = product
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
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        controller.cancel()
                    }
                }
            }
        }
        .task {
            await controller.refreshConnectivity()
        }
        .onChange(of: controller.phase) { _, newPhase in
            if case .idle = newPhase {
                dismiss()
            }
        }
        .alert(
            "Food lookup",
            isPresented: Binding(
                get: { lookupError != nil },
                set: { isPresented in
                    if !isPresented {
                        lookupError = nil
                    }
                }
            ),
            actions: {
                Button("OK", role: .cancel) {
                    lookupError = nil
                }
            },
            message: {
                if let lookupError {
                    Text(lookupError)
                }
            }
        )
    }

    @ViewBuilder
    private var barcodeStep: some View {
        if isResolvingBarcode {
            VStack(spacing: HelmSpacing.md) {
                ProgressView()
                Text("Looking up product…")
                    .helmType(.body, color: HelmColor.fgMuted)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .helmScreenBackground()
        } else {
            BarcodeScannerView(
                onBarcode: { barcode in
                    resolveBarcode(barcode)
                },
                onCancel: {
                    controller.cancel()
                }
            )
        }
    }

    private func resolveBarcode(_ barcode: String) {
        isResolvingBarcode = true
        Task {
            do {
                let product = try await controller.resolveBarcode(barcode)
                selectedProduct = product
            } catch {
                lookupError = controller.isBusy ? "Could not look up that barcode." : lookupMessage(for: error)
            }
            isResolvingBarcode = false
        }
    }

    private func lookupMessage(for error: Error) -> String {
        switch error {
        case FoodResolverError.offline:
            "Branded lookup needs a network connection."
        case FoodResolverError.notFound:
            "No product found for that barcode."
        default:
            "Could not look up that barcode."
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
