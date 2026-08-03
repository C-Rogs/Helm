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
                    PhotoLogOptionRow(title: "Choose photo", icon: .photo)
                }
                .buttonStyle(.helmPressable)

                Button {
                    onCamera()
                    onCancel()
                } label: {
                    PhotoLogOptionRow(title: "Camera", icon: .camera)
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

private struct PhotoLogOptionRow: View {
    let title: String
    let icon: HelmIcon

    var body: some View {
        Label(title, helmIcon: icon, context: .inline)
            .helmType(.label, color: HelmColor.buttonSecondaryForeground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, HelmSpacing.sm)
            .helmPanelChrome(.elevated, cornerRadius: HelmRadius.sm)
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
