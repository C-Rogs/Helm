import DesignSystem
import PhotosUI
import SwiftUI

struct PhotoLogOptionsSheet: View {
    @Binding var pickerItem: PhotosPickerItem?
    @Binding var userNotes: String
    let onCamera: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                Text("Estimate macros from a meal photo.")
                    .helmType(.body, color: HelmColor.fgMuted)

                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    Text("Context (optional)")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                    TextField("e.g. didn't eat the skin", text: $userNotes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2 ... 4)
                }

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
        .presentationDetents([.medium, .large])
    }
}

#Preview("Photo options") {
    PhotoLogOptionsSheet(
        pickerItem: .constant(nil),
        userNotes: .constant(""),
        onCamera: {},
        onCancel: {}
    )
    .helmTheme()
}
