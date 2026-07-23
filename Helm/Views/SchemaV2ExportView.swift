import DesignSystem
import ExportKit
import HealthKitIngest
import SwiftUI
import UIKit

struct SchemaV2ExportView: View {
    @State private var window = SchemaV2ExportWindow.defaultWindow()
    @State private var isExporting = false
    @State private var lastJSON: String?
    @State private var shareItem: ExportShareItem?
    @State private var showCopiedBanner = false
    @State private var errorMessage: String?
    @State private var importedDayCount: Int?

    var body: some View {
        List {
            if let importedDayCount {
                Section {
                    Text("Shared import loaded: \(importedDayCount) day(s) in app group cache.")
                        .font(HelmType.body.font)
                        .foregroundStyle(HelmColor.fgMuted)
                }
            }

            Section("Export window") {
                DatePicker("Start", selection: $window.start, displayedComponents: .date)
                DatePicker("End", selection: $window.end, displayedComponents: .date)
                Text("Sleep uses bioharvest’s 18:00–18:00 window. Other metrics use local calendar days.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgMuted)
            }

            Section("Actions") {
                Button(isExporting ? "Exporting…" : "Export schema v2 JSON") {
                    Task { await exportJSON() }
                }
                .disabled(isExporting || !window.isValid)

                Button("Copy to Gemini") {
                    copyToGemini()
                }
                .disabled(lastJSON == nil)

                Button("Share JSON") {
                    shareJSON()
                }
                .disabled(lastJSON == nil)
            }

            Section {
                Text("Manual fallback: export matches bioharvest schema v2 (`app: bioharvest`). Copy pastes into Gemini with a short handoff header. Share Extension imports JSON shared from bioharvest or Files.")
                    .font(HelmType.body.font)
                    .foregroundStyle(HelmColor.fgMuted)
            }
        }
        .navigationTitle("Schema v2 Export")
        .overlay(alignment: .top) {
            if showCopiedBanner {
                Text("Copied for Gemini")
                    .font(HelmType.label.font)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(.top, 8)
            }
        }
        .alert("Export failed", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $shareItem) { item in
            ShareSheetView(activityItems: [item.url])
        }
        .task {
            await refreshImportedSummary()
        }
    }

    @MainActor
    private func exportJSON() async {
        isExporting = true
        defer { isExporting = false }

        do {
            let (_, data) = try await SchemaV2ExportService.buildExport(window: window)
            guard let json = String(data: data, encoding: .utf8) else {
                errorMessage = "Failed to read export JSON."
                return
            }
            lastJSON = json
            HapticEngine.shared.play(.selection)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func copyToGemini() {
        guard let lastJSON else { return }
        UIPasteboard.general.string = GeminiClipboardHandoff.clipboardText(json: lastJSON)
        showCopiedBanner = true
        HapticEngine.shared.play(.selection)
        if let url = GeminiClipboardHandoff.geminiAppURL {
            UIApplication.shared.open(url)
        }
        Task {
            try? await Task.sleep(for: .seconds(2))
            await MainActor.run {
                withAnimation { showCopiedBanner = false }
            }
        }
    }

    private func shareJSON() {
        guard let lastJSON else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("Helm_SchemaV2_\(Int(Date().timeIntervalSince1970)).json")
        do {
            try lastJSON.write(to: url, atomically: true, encoding: .utf8)
            shareItem = ExportShareItem(url: url)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshImportedSummary() async {
        if AppGroupExportStore.consumePendingImport(),
           let payload = try? SchemaV2ExportService.importSharedExport() {
            importedDayCount = payload.logs.count
        }
    }
}

private struct ExportShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

private struct ShareSheetView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    NavigationStack {
        SchemaV2ExportView()
    }
    .helmTheme()
}
