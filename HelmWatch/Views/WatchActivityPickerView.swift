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
                    Spacer()
                    if store.selectedActivity == activity {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle("Activity")
    }
}
