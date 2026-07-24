import DesignSystem
import PhotosUI
import SwiftUI

struct PhotoLogOptionsSheet: View {
    @Binding var pickerItem: PhotosPickerItem?
    let onCamera: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                Text("Estimate macros from a meal photo.")
                    .helmType(.body, color: HelmColor.fgMuted)

                PhotosPicker(
                    selection: $pickerItem,
                    matching: .images,
                    photoLibrary: .shared()
                ) {
                    Label("Choose photo", helmIcon: .photo, context: .inline)
                        .font(HelmTypography.headline)
                        .foregroundStyle(HelmColor.buttonSecondaryForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HelmSpacing.sm)
                        .background(
                            HelmColor.buttonSecondaryBackground,
                            in: RoundedRectangle(cornerRadius: HelmRadius.sm)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: HelmRadius.sm)
                                .strokeBorder(HelmColor.buttonSecondaryBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.helmPressable)
                .onChange(of: pickerItem) { _, item in
                    if item != nil {
                        onCancel()
                    }
                }

                Button {
                    onCamera()
                    onCancel()
                } label: {
                    Label("Camera", helmIcon: .camera, context: .inline)
                        .font(HelmTypography.headline)
                        .foregroundStyle(HelmColor.buttonSecondaryForeground)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, HelmSpacing.sm)
                        .background(
                            HelmColor.buttonSecondaryBackground,
                            in: RoundedRectangle(cornerRadius: HelmRadius.sm)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: HelmRadius.sm)
                                .strokeBorder(HelmColor.buttonSecondaryBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(.helmPressable)

                Spacer()
            }
            .padding(HelmSpacing.md)
            .helmScreenBackground()
            .navigationTitle("Log from photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview("Photo options") {
    PhotoLogOptionsSheet(pickerItem: .constant(nil), onCamera: {}, onCancel: {})
        .helmTheme()
}
