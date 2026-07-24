import Core
import DesignSystem
import Foundation
import HealthKitIngest
import ReadinessKit
import SwiftUI

struct RecoveryDetailContainer: View {
    let score: ReadinessScore
    var matchedCardNamespace: Namespace.ID?

    @State private var model: RecoveryDetailModel?
    @State private var historyPoints: [ReadinessHistoryPoint] = []
    @Bindable private var chatController = ChatBootstrap.controller

    private var briefService: BriefService { BriefBootstrap.briefService }

    var body: some View {
        Group {
            if let model {
                RecoveryDetailView(
                    model: model,
                    historyPoints: historyPoints,
                    matchedCardNamespace: matchedCardNamespace,
                    onAskCoach: chatController.requestCoachHandoff(prompt:)
                )
            } else {
                ScrollView {
                    HelmLoadingState(rowCount: 4)
                        .helmScreenPadding()
                }
                .helmScreenBackground()
                .navigationTitle("Recovery")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            await load()
        }
    }

    @MainActor
    private func load() async {
        let briefModel: (narration: String?, isEngineOnly: Bool) = {
            guard case let .ready(brief) = briefService.state else {
                return (nil, true)
            }
            return (brief.narration, brief.isEngineOnly)
        }()

        do {
            let loaded = try RecoveryDetailBuilder.load(
                store: PersistenceBootstrap.persistenceStore,
                score: score,
                briefNarration: briefModel.narration,
                briefIsEngineOnly: briefModel.isEngineOnly,
                coachAvailable: chatController.isCoachAvailable
            )
            model = loaded.model
            historyPoints = loaded.history
        } catch {
            model = RecoveryDetailBuilder.build(
                context: RecoveryDetailBuilder.BuildContext(
                    score: score,
                    baseline: nil,
                    sleepHours: nil,
                    history: [],
                    briefNarration: briefModel.narration,
                    briefIsEngineOnly: briefModel.isEngineOnly,
                    coachAvailable: chatController.isCoachAvailable
                )
            )
            historyPoints = []
        }
    }
}
