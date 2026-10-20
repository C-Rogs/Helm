import DesignSystem
import HealthKitIngest
import SwiftUI
import UIKit

struct MealPhotoFullScreenCover: View {
    let image: UIImage
    let title: String?
    let subtitle: String?
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView([.horizontal, .vertical]) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(HelmSpacing.md)
            }
            .background(Color.black.ignoresSafeArea())
            .navigationTitle(title ?? "Meal photo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: onDismiss)
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black.opacity(0.85), for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .overlay(alignment: .bottomLeading) {
            if let subtitle {
                Text(subtitle)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                    .padding(HelmSpacing.md)
            }
        }
        .preferredColorScheme(.dark)
    }
}

struct MealPhotoHeroButton: View {
    let mealID: UUID
    let mealName: String
    let loggedAt: Date

    @State private var image: UIImage?
    @State private var showsFullScreen = false

    var body: some View {
        Group {
            if let image {
                Button {
                    showsFullScreen = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("View photo for \(mealName)")
            }
        }
        .task(id: mealID) {
            image = await Task.detached(priority: .utility) {
                MealPhotoStore.loadImage(mealID: mealID)
            }.value
        }
        .fullScreenCover(isPresented: $showsFullScreen) {
            if let image {
                MealPhotoFullScreenCover(
                    image: image,
                    title: mealName,
                    subtitle: loggedAt.formatted(date: .abbreviated, time: .shortened),
                    onDismiss: { showsFullScreen = false }
                )
            }
        }
    }
}

#if DEBUG
#Preview("Meal photo hero") {
    MealPhotoHeroButton(
        mealID: UUID(),
        mealName: "Chicken bowl",
        loggedAt: Date()
    )
    .padding()
    .helmTheme()
}
#endif
