import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct ProgressionDetailContainer: View {
    var matchedCardNamespace: Namespace.ID? = nil

    @State private var model: ProgressionDetailModel?

    var body: some View {
        Group {
            if let model {
                ProgressionDetailView(
                    model: model,
                    matchedCardNamespace: matchedCardNamespace
                )
            } else {
                ScrollView {
                    HelmLoadingState(rowCount: 4)
                        .helmScreenPadding()
                }
                .helmScreenBackground()
                .navigationTitle("Progression")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        do {
            let readiness = ReadinessBootstrap.readinessService.state.score
            model = try await ProgressionDetailBuilder.load(
                store: PersistenceBootstrap.persistenceStore,
                engine: PlanBootstrap.engine,
                readiness: readiness
            )
        } catch {
            model = ProgressionDetailBuilder.coldStartFallback()
        }
    }
}
