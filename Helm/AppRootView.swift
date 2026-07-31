import DesignSystem
import ExportKit
import HealthKitIngest
import SwiftUI

struct AppRootView: View {
    @State private var onboardingStore = OnboardingStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if onboardingStore.shouldPresent {
                OnboardingFlowView(onFinished: {})
            } else {
                RootTabView()
            }
        }
        .helmTheme()
        .onChange(of: scenePhase) { _, newPhase in
            AppLifecycleState.update(scenePhase: newPhase)
        }
        .onAppear {
            AppLifecycleState.update(scenePhase: scenePhase)
        }
        .onReceive(NotificationCenter.default.publisher(for: LiveActivityCompleteSetBridge.notificationName)) { note in
            guard
                let exerciseID = note.userInfo?[LiveActivityCompleteSetBridge.sessionExerciseIDKey] as? String,
                let setID = note.userInfo?[LiveActivityCompleteSetBridge.setIDKey] as? String
            else { return }
            Task {
                await TrainBootstrap.sessionController.completeSet(
                    sessionExerciseID: exerciseID,
                    setID: setID
                )
            }
        }
        .onOpenURL { url in
            guard AppGroupExportStore.matchesImportURL(url) else { return }
            consumeSchemaV2ShareImportIfNeeded()
        }
        .onAppear {
            consumeSchemaV2ShareImportIfNeeded()
        }
    }

    @MainActor
    private func consumeSchemaV2ShareImportIfNeeded() {
        guard AppGroupExportStore.consumePendingImport() else { return }
        _ = try? SchemaV2ExportService.importSharedExport()
    }
}

#Preview {
    AppRootView()
}
