import DesignSystem
import ExportKit
import HealthKitIngest
import SwiftUI

struct AppRootView: View {
    @State private var onboardingStore = OnboardingStore.shared
    @Environment(\.scenePhase) private var scenePhase

    // MARK: - Body

    var body: some View {
        Group {
            if onboardingStore.shouldPresent {
                OnboardingFlowView(onFinished: {})
            } else {
                RootTabView()
            }
        }
        .helmTheme()
        .helmCoachApplyWaveOverlay()
        .onChange(of: scenePhase) { _, newPhase in
            AppLifecycleState.update(scenePhase: newPhase)
            switch newPhase {
            case .active:
                SpotifyAppRemoteService.shared.handleAppBecomeActive()
                Task { @MainActor in
                    await RestNotificationRouter.processPendingIfForeground()
                }
            case .inactive, .background:
                SpotifyAppRemoteService.shared.handleAppResignActive()
                if newPhase == .background {
                    CloudBackupCoordinator.shared.schedulePush()
                }
            @unknown default:
                break
            }
        }
        .onAppear {
            AppLifecycleState.update(scenePhase: scenePhase)
        }
        .onReceive(NotificationCenter.default.publisher(for: LiveActivityCompleteSetBridge.notificationName)) { note in
            guard
                let exerciseID = note.userInfo?[LiveActivityCompleteSetBridge.sessionExerciseIDKey] as? String,
                let setID = note.userInfo?[LiveActivityCompleteSetBridge.setIDKey] as? String
            else { return }
            let eventID = note.userInfo?[LiveActivityCompleteSetBridge.eventIDKey] as? String
            Task { @MainActor in
                await TrainBootstrap.sessionController.completeSetIfNeeded(
                    sessionExerciseID: exerciseID,
                    setID: setID
                )
                if let eventID, !eventID.isEmpty {
                    WatchReadinessBootstrap.coordinator.acknowledgeCompleteSet(eventID: eventID)
                }
            }
        }
        .onOpenURL { url in
            handleIncomingURL(url)
        }
        .onAppear {
            consumeSchemaV2ShareImportIfNeeded()
        }
    }

    /// Single entry point for `helm://` URLs. SwiftUI delivers an incoming URL to
    /// only one `onOpenURL` handler per scene, so every deep link routes here.
    @MainActor
    private func handleIncomingURL(_ url: URL) {
        // Only the Spotify app switch lands here; the web sign-in consumes its own callback.
        if SpotifyAppRemoteService.shared.handleRedirect(url) { return }
        if AppGroupExportStore.matchesImportURL(url) {
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
