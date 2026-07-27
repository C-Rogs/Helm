import Core
import DesignSystem
import HealthKitIngest
import SwiftUI

struct FoodSearchView: View {
    let isOnline: Bool
    let onSelect: (ResolvedFoodProduct) -> Void

    @State private var query = ""
    @State private var results: [FoodSearchResult] = []
    @State private var recents: [ResolvedFoodProduct] = []
    @State private var isSearching = false
    @State private var searchTask: Task<Void, Never>?
    @State private var remoteSearchMessage: String?
    @State private var hasSubmittedRemoteSearch = false

    private let controller: ManualFoodLogController

    init(controller: ManualFoodLogController, isOnline: Bool, onSelect: @escaping (ResolvedFoodProduct) -> Void) {
        self.controller = controller
        self.isOnline = isOnline
        self.onSelect = onSelect
    }

    var body: some View {
        VStack(spacing: 0) {
            if !isOnline {
                offlineBanner
            }

            List {
                if !recents.isEmpty, trimmedQuery.isEmpty {
                    Section {
                        recentsStrip
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(HelmColor.surface)
                }

                if let remoteSearchMessage {
                    Text(remoteSearchMessage)
                        .helmType(.body, color: HelmColor.fgSecondary)
                        .listRowBackground(HelmColor.surface)
                }

                if isSearching {
                    HStack(spacing: HelmSpacing.sm) {
                        ProgressView()
                        Text("Searching foods…")
                            .helmType(.body, color: HelmColor.fgMuted)
                    }
                    .listRowBackground(HelmColor.surface)
                } else if trimmedQuery.isEmpty {
                    Text("Search CoFID and scanned products on-device. Press Search for new branded products.")
                        .helmType(.body, color: HelmColor.fgMuted)
                        .listRowBackground(HelmColor.surface)
                } else if results.isEmpty {
                    if !isOnline {
                        offlineMissState
                    } else if !hasSubmittedRemoteSearch {
                        Text("No local matches for \"\(trimmedQuery)\". Press Search to check branded products.")
                            .helmType(.body, color: HelmColor.fgMuted)
                            .listRowBackground(HelmColor.surface)
                    } else {
                        Text("No matches for \"\(trimmedQuery)\".")
                            .helmType(.body, color: HelmColor.fgMuted)
                            .listRowBackground(HelmColor.surface)
                    }
                } else {
                    ForEach(results, id: \.product.ref.cacheKey) { result in
                        Button {
                            onSelect(result.product)
                        } label: {
                            FoodSearchResultRow(product: result.product)
                        }
                        .buttonStyle(.helmPressable)
                        .listRowBackground(HelmColor.surface)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .searchable(text: $query, prompt: "Search foods")
        .navigationTitle("Search food")
        .navigationBarTitleDisplayMode(.inline)
        .onSubmit(of: .search) {
            Task { await submitRemoteSearch() }
        }
        .onChange(of: query) { _, newValue in
            hasSubmittedRemoteSearch = false
            remoteSearchMessage = nil
            scheduleLocalSearch(for: newValue)
        }
        .task {
            await controller.refreshConnectivity()
            recents = await controller.fetchRecents()
        }
    }

    private var recentsStrip: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            Text("Recent")
                .helmType(.monoTag, color: HelmColor.fgMuted)
                .padding(.horizontal, HelmSpacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HelmSpacing.xs) {
                    ForEach(recents, id: \.ref.cacheKey) { product in
                        Button {
                            onSelect(product)
                        } label: {
                            recentChip(product)
                        }
                        .buttonStyle(.helmPressable)
                    }
                }
                .padding(.horizontal, HelmSpacing.md)
                .padding(.bottom, HelmSpacing.xs)
            }
        }
        .padding(.top, HelmSpacing.sm)
    }

    private func recentChip(_ product: ResolvedFoodProduct) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Text(product.ref.displayName)
                .helmType(.label)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let serving = product.servingLabel {
                Text(serving)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            } else if let grams = product.suggestedGrams {
                Text("\(Int(grams.rounded())) g")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
        }
        .frame(width: 132, alignment: .leading)
        .padding(HelmSpacing.sm)
        .background(HelmColor.gaugeTrack.opacity(0.25), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
    }

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var offlineBanner: some View {
        HStack(spacing: HelmSpacing.sm) {
            HelmIconView(.offline, context: .inline)
                .foregroundStyle(HelmColor.compromised)
            Text("Offline. CoFID and recents only; branded search needs a connection.")
                .helmType(.body, color: HelmColor.fgSecondary)
        }
        .padding(HelmSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HelmColor.compromised.opacity(0.12))
    }

    private var offlineMissState: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("No offline match for \"\(trimmedQuery)\".")
                .helmType(.body, color: HelmColor.fgMuted)
            Text("Try a generic food name, use a recent item, or log with a photo.")
                .helmType(.body, color: HelmColor.fgSecondary)
        }
        .listRowBackground(HelmColor.surface)
    }

    private func scheduleLocalSearch(for query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            isSearching = false
            return
        }

        isSearching = true
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            do {
                let hits = try await controller.searchLocal(query: trimmed)
                guard !Task.isCancelled else { return }
                results = hits
            } catch {
                guard !Task.isCancelled else { return }
                results = []
            }
            isSearching = false
        }
    }

    private func submitRemoteSearch() async {
        searchTask?.cancel()
        let trimmed = trimmedQuery
        guard trimmed.count >= 3 else {
            remoteSearchMessage = "Enter at least 3 characters to search branded products."
            return
        }
        guard isOnline else {
            remoteSearchMessage = "Branded search needs a network connection."
            return
        }

        isSearching = true
        remoteSearchMessage = nil
        defer { isSearching = false }

        do {
            let hits = try await controller.searchRemote(query: trimmed)
            results = hits
            hasSubmittedRemoteSearch = true
        } catch FoodResolverError.rateLimited {
            remoteSearchMessage = "Too many searches. Wait a minute and try again."
        } catch FoodResolverError.queryTooShort {
            remoteSearchMessage = "Enter at least 3 characters to search branded products."
        } catch {
            remoteSearchMessage = "Branded search failed. Local results are still shown."
        }
    }
}

private struct FoodSearchResultRow: View {
    let product: ResolvedFoodProduct

    var body: some View {
        HStack(alignment: .top, spacing: HelmSpacing.sm) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text(product.ref.displayName)
                    .helmType(.label)
                    .foregroundStyle(HelmColor.fg)
                Text(sourceLabel)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
            Spacer()
            Text("\(Self.format(product.per100gKcal)) kcal / 100 g")
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
        .padding(.vertical, HelmSpacing.xxs)
    }

    private var sourceLabel: String {
        switch product.source {
        case .recent:
            "Recent"
        case .productCache:
            product.ref.origin == .openFoodFacts ? "Branded cache" : "Saved"
        case .cofid:
            "CoFID"
        case .openFoodFacts:
            "Branded"
        case .custom:
            "Custom"
        }
    }

    private static func format(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value.rounded()))
        }
        return String(format: "%.0f", value)
    }
}

#Preview("Food search online") {
    NavigationStack {
        FoodSearchView(
            controller: ManualFoodLogController.previewController(online: true),
            isOnline: true,
            onSelect: { _ in }
        )
    }
    .helmTheme()
}

#Preview("Food search offline") {
    NavigationStack {
        FoodSearchView(
            controller: ManualFoodLogController.previewController(online: false),
            isOnline: false,
            onSelect: { _ in }
        )
    }
    .helmTheme()
}
