import Core
import SwiftUI

struct WatchActivityPickerView: View {
    @Bindable var store: WatchWorkoutSessionStore

    var body: some View {
        List(WatchWorkoutActivityKind.allCases) { activity in
            Button {
                store.selectActivity(activity)
            } label: {
                HStack {
                    Text(activity.displayName)
                        .font(WatchType.label.font)
                        .foregroundStyle(WatchPalette.fg)
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
        .navigationTitle("Activity")
        .helmWatchScreenBackground()
    }
}