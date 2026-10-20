import Core
import DesignSystem
import Diagnostics
import HealthKitIngest
import Persistence
import SwiftUI
import UIKit

private struct MealPhotoGalleryItem: Identifiable, Equatable {
    let meal: MealRecord
    let id: UUID

    init(meal: MealRecord) {
        self.meal = meal
        self.id = meal.id
    }
}

@MainActor
@Observable
private final class MealPhotoGalleryLoader {
    private(set) var items: [MealPhotoGalleryItem] = []
    private(set) var isLoading = false
    private(set) var hasMore = true

    private let pageSize = 40
    private var dbOffset = 0
    private var isExhausted = false

    func loadInitial() async {
        guard items.isEmpty, !isLoading else { return }
        await loadMoreIfNeeded(force: true)
    }

    func loadMoreIfNeeded(force: Bool = false) async {
        guard !isLoading else { return }
        if !force, !hasMore { return }

        isLoading = true
        defer { isLoading = false }

        let store = PersistenceBootstrap.persistenceStore
        var appended: [MealPhotoGalleryItem] = []

        while appended.count < pageSize / 2, !isExhausted {
            let batch: [MealRecord]
            do {
                batch = try store.nutrition.fetchPhotoMeals(limit: pageSize, offset: dbOffset)
            } catch {
                hasMore = false
                isExhausted = true
                return
            }

            if batch.isEmpty {
                isExhausted = true
                hasMore = false
                break
            }

            dbOffset += batch.count
            if batch.count < pageSize {
                isExhausted = true
            }

            let withPhotos = batch.filter { MealPhotoStore.exists(mealID: $0.id) }
            appended.append(contentsOf: withPhotos.map(MealPhotoGalleryItem.init(meal:)))

            if isExhausted {
                hasMore = false
            }
        }

        let existingIDs = Set(items.map(\.id))
        let newItems = appended.filter { !existingIDs.contains($0.id) }
        items.append(contentsOf: newItems)
        if newItems.isEmpty, !isExhausted {
            await loadMoreIfNeeded(force: true)
        }
    }
}

struct MealPhotoGalleryView: View {
    @State private var loader = MealPhotoGalleryLoader()
    @State private var selectedItem: MealPhotoGalleryItem?
    @State private var shareURLs: [URL]?
    @State private var exportShareItem: ExportShareItem?

    private let columns = [
        GridItem(.flexible(), spacing: HelmSpacing.sm),
        GridItem(.flexible(), spacing: HelmSpacing.sm),
        GridItem(.flexible(), spacing: HelmSpacing.sm)
    ]

    var body: some View {
        Group {
            if loader.items.isEmpty, loader.isLoading {
                ProgressView("Loading photos…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if loader.items.isEmpty {
                emptyState
            } else {
                galleryGrid
            }
        }
        .navigationTitle("Meal photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !loader.items.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Export visible photos") {
                            exportVisiblePhotos()
                        }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Export meal photos")
                }
            }
        }
        .task {
            await loader.loadInitial()
        }
        .sheet(item: $selectedItem) { item in
            MealPhotoGalleryDetailSheet(
                item: item,
                onShare: { url in
                    exportShareItem = ExportShareItem(url: url)
                }
            )
        }
        .sheet(item: $exportShareItem) { item in
            ShareSheet(items: [item.url])
        }
        .sheet(isPresented: Binding(
            get: { shareURLs != nil },
            set: { if !$0 { shareURLs = nil } }
        )) {
            if let shareURLs {
                ShareSheet(items: shareURLs)
            }
        }
        .helmScreenBackground()
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No meal photos", systemImage: HelmIcon.photo.rawValue)
        } description: {
            Text("Log a meal with Photo on the Nutrition tab.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var galleryGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: HelmSpacing.sm) {
                ForEach(loader.items) { item in
                    MealPhotoGalleryCell(item: item)
                        .onTapGesture {
                            selectedItem = item
                        }
                        .onAppear {
                            if item.id == loader.items.last?.id {
                                Task { await loader.loadMoreIfNeeded() }
                            }
                        }
                }
            }
            .padding(HelmSpacing.md)

            if loader.isLoading {
                ProgressView()
                    .padding(.bottom, HelmSpacing.lg)
            }
        }
    }

    private func exportVisiblePhotos() {
        Task {
            var urls: [URL] = []
            for item in loader.items.prefix(20) {
                if let url = try? MealPhotoStore.fileURL(for: item.meal.id),
                   FileManager.default.fileExists(atPath: url.path) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            shareURLs = urls
        }
    }
}

private struct MealPhotoGalleryCell: View {
    let item: MealPhotoGalleryItem

    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            Group {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                } else {
                    Rectangle()
                        .fill(HelmColor.gaugeTrack.opacity(0.35))
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: HelmRadius.sm))

            Text(item.meal.name)
                .helmType(.monoTag)
                .lineLimit(1)
            Text(item.meal.loggedAt.formatted(date: .abbreviated, time: .omitted))
                .helmType(.monoTag, color: HelmColor.fgMuted)
                .lineLimit(1)
        }
        .task(id: item.id) {
            thumbnail = await Task.detached(priority: .utility) {
                MealPhotoStore.loadThumbnail(mealID: item.meal.id)
            }.value
        }
    }
}

private struct MealPhotoGalleryDetailSheet: View {
    let item: MealPhotoGalleryItem
    let onShare: (URL) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var showsFullScreen = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    if let image {
                        Button {
                            showsFullScreen = true
                        } label: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 240)
                                .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))
                        }
                        .buttonStyle(.plain)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .frame(height: 240)
                    }

                    Text(item.meal.name)
                        .helmType(.title)
                    Text(item.meal.loggedAt.formatted(date: .complete, time: .shortened))
                        .helmType(.body, color: HelmColor.fgMuted)
                    Text(item.meal.bucket.displayName)
                        .helmType(.monoTag, color: HelmColor.fgMuted)

                    if let kcal = item.meal.energy?.kilocalories, kcal > 0 {
                        Text("\(Int(kcal.rounded())) kcal")
                            .helmType(.body, color: HelmColor.fgSecondary)
                    }
                }
                .padding(HelmSpacing.md)
            }
            .navigationTitle("Meal photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Share") {
                        shareCurrentPhoto()
                    }
                    .disabled(image == nil)
                }
            }
        }
        .task(id: item.id) {
            image = await Task.detached(priority: .utility) {
                MealPhotoStore.loadImage(mealID: item.meal.id)
            }.value
        }
        .fullScreenCover(isPresented: $showsFullScreen) {
            if let image {
                MealPhotoFullScreenCover(
                    image: image,
                    title: item.meal.name,
                    subtitle: item.meal.loggedAt.formatted(date: .abbreviated, time: .shortened),
                    onDismiss: { showsFullScreen = false }
                )
            }
        }
    }

    private func shareCurrentPhoto() {
        guard let url = try? MealPhotoStore.fileURL(for: item.meal.id),
              FileManager.default.fileExists(atPath: url.path) else {
            return
        }
        onShare(url)
    }
}

#if DEBUG
#Preview("Meal photo gallery") {
    NavigationStack {
        MealPhotoGalleryView()
    }
    .helmTheme()
}
#endif
