import DesignSystem
import SwiftUI

struct MuscleVolumeBoardContainer: View {
    @Bindable private var boardStore = MuscleVolumeBootstrap.store
    var matchedCardNamespace: Namespace.ID? = nil

    var body: some View {
        Group {
            if boardStore.isLoading, boardStore.model == nil {
                ScrollView {
                    HelmLoadingState(rowCount: 4)
                        .helmScreenPadding()
                }
                .helmScreenBackground()
                .navigationTitle("Muscle volume")
                .navigationBarTitleDisplayMode(.inline)
            } else if let model = boardStore.model {
                ScrollView {
                    Card {
                        MuscleVolumeBoardView(model: model, showsHeader: true)
                    }
                    .helmMatchedCard(id: "muscle-volume", namespace: matchedCardNamespace)
                    .helmScreenPadding()
                }
                .helmScreenBackground()
                .navigationTitle("Muscle volume")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ScrollView {
                    HelmEmptyState(
                        title: "Volume board is quiet",
                        message: "Start today's session or log a workout to fill the last 7 days.",
                        icon: .train
                    )
                    .helmScreenPadding()
                }
                .helmScreenBackground()
                .navigationTitle("Muscle volume")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            boardStore.refresh()
        }
    }
}

#Preview("Muscle volume detail") {
    NavigationStack {
        ScrollView {
            Card {
                MuscleVolumeBoardView(model: .stateCoverageFixture)
            }
            .helmScreenPadding()
        }
        .helmScreenBackground()
        .navigationTitle("Muscle volume")
    }
    .helmTheme()
}

#Preview("Muscle volume detail data sheet") {
    NavigationStack {
        ScrollView {
            Card {
                MuscleVolumeBoardView(model: .stateCoverageFixture)
            }
            .helmScreenPadding()
        }
        .helmScreenBackground()
        .navigationTitle("Muscle volume")
    }
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}
