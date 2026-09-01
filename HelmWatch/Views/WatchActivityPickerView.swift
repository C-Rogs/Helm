import Core
import SwiftUI

struct WatchActivityPickerView: View {
    @Bindable var store: WatchWorkoutSessionStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(WatchWorkoutActivityKind.allCases) { activity in
                Button {
                    store.selectActivity(activity)
                    WatchHaptic.selection.play()
                } label: {
                    HStack {
                        Text(activity.displayName)
                            .watchType(.label)
                        Spacer()
                        if store.selectedActivity == activity {
                            Image(systemName: "checkmark")
                                .foregroundStyle(WatchPalette.accent)
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(WatchPalette.surfaceElevated)
            }

            Button {
                WatchHaptic.sessionStart.play()
                Task {
                    await store.startWorkout()
                    if store.phase == .active || store.phase == .paused {
                        dismiss()
                    } else {
                        WatchHaptic.failure.play()
                    }
                }
            } label: {
                Text("Start")
                    .watchType(.label, color: WatchPalette.buttonPrimaryForeground)
                    .frame(maxWidth: .infinity, minHeight: WatchLayout.hit)
            }
            .listRowBackground(WatchPalette.accent)
        }
        .navigationTitle("Activity")
        .helmWatchScreenBackground()
    }
}
