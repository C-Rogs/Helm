import Core
import DesignSystem
import Persistence
import SwiftUI

struct SleepAnalysisContainer: View {
    @State private var model: SleepAnalysisModel?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let model {
                SleepAnalysisView(model: model)
            } else if let errorMessage {
                ScrollView {
                    HelmErrorState(
                        title: "Sleep unavailable",
                        message: errorMessage,
                        onRetry: { Task { await load() } }
                    )
                    .helmScreenPadding()
                }
                .helmScreenBackground()
                .navigationTitle("Sleep")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ScrollView {
                    HelmLoadingState(rowCount: 3)
                        .helmScreenPadding()
                }
                .helmScreenBackground()
                .navigationTitle("Sleep")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .task {
            await load()
        }
    }

    @MainActor
    private func load() async {
        errorMessage = nil
        let store = PersistenceBootstrap.persistenceStore
        do {
            let loaded = try await Task.detached(priority: .userInitiated) {
                try SleepAnalysisBuilder.load(store: store)
            }.value
            model = loaded
        } catch {
            model = nil
            errorMessage = error.localizedDescription
        }
    }
}
