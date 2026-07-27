import Core
import DesignSystem
import SwiftUI

struct OfflineBarcodeQueueSheet: View {
    let barcode: String
    @Binding var bucket: MealBucket
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                Text("Barcode \(barcode) will be saved without macros and matched when you are back online.")
                    .helmType(.body, color: HelmColor.fgSecondary)

                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    MealBucketPicker(selection: $bucket)
                }

                Spacer()
            }
            .padding(HelmSpacing.md)
            .helmScreenBackground()
            .navigationTitle("Save for later")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save pending", action: onSave)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
