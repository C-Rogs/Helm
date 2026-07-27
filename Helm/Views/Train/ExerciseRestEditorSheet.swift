import DesignSystem
import SwiftUI

struct ExerciseRestEditorSheet: View {
    let exerciseName: String
    let currentSeconds: Int
    let onSelect: (Int) -> Void

    @Environment(\.dismiss) private var dismiss

    private let presets = [60, 90, 120, 180]

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                Text("Rest between sets for \(exerciseName)")
                    .helmType(.body, color: HelmColor.fgSecondary)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: HelmSpacing.sm) {
                    ForEach(presets, id: \.self) { seconds in
                        Button {
                            onSelect(seconds)
                            dismiss()
                        } label: {
                            VStack(spacing: HelmSpacing.xxs) {
                                Text("\(seconds)s")
                                    .helmType(.bigNumber, color: seconds == currentSeconds ? HelmColor.accent : HelmColor.fg)
                                if seconds == currentSeconds {
                                    Text("Current")
                                        .helmType(.monoTag, color: HelmColor.accent)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .padding(HelmSpacing.md)
                            .background(HelmColor.surfaceElevated, in: RoundedRectangle(cornerRadius: HelmRadius.md))
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(HelmSpacing.md)
            .helmScreenBackground()
            .navigationTitle("Rest timer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
