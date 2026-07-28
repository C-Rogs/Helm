import DesignSystem
import SwiftUI

struct WeekAheadScheduleSection: View {
    @Bindable var store: WeekAheadScheduleStore

    var body: some View {
        if store.isLoading, store.model == nil {
            HelmSkeletonCard(rowCount: 3)
        } else if let model = store.model, !model.isEmpty {
            Card {
                WeekAheadScheduleView(model: model)
            }
        }
    }
}

#if DEBUG
#Preview("Week ahead section") {
    ScrollView {
        WeekAheadScheduleSection(store: WeekAheadScheduleBootstrap.store)
            .helmScreenPadding()
    }
    .helmTheme()
}
#endif
