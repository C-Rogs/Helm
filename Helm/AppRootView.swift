import DesignSystem
import ExportKit
import HealthKitIngest
import SwiftUI

struct AppRootView: View {
    @State private var onboardingStore = OnboardingStore.shared

    var body: some View {
        Group {
            if onboardingStore.shouldPresent {
                OnboardingFlowView(onFinished: {})
            } else {
                RootTabView()
            }
        }
        .helmTheme()
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
