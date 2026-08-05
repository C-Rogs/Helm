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
                    .modifier(MatchedCardModifier(id: "muscle-volume", namespace: matchedCardNamespace))
                    .helmScreenPadding()
                }
                .helmScreenBackground()
                .navigationTitle("Muscle volume")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ScrollView {
                    HelmEmptyState(
                        title: "No volume data",
                        message: "Log training this week to see per-muscle volume.",
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

private struct MatchedCardModifier: ViewModifier {
    let id: String
    let namespace: Namespace.ID?

    func body(content: Content) -> some View {
        if let namespace {
            content.helmMatchedCardDetail(id: id, in: namespace, isSource: false)
        } else {
            content
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
