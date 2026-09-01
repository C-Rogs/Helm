import Core
import DesignSystem
import SwiftUI

enum BucketFoodLogAction {
    case describe
    case search
    case barcode
    case photo
    case quickAdd
    case alcohol
    case savedMeals
}

struct BucketFoodLogMenu: View {
    let bucket: MealBucket
    let isPhotoAvailable: Bool
    var isDescribeAvailable = true
    let onAction: (BucketFoodLogAction) -> Void

    var body: some View {
        Menu {
            Button("Search") {
                onAction(.search)
            }
            Button("Barcode") {
                onAction(.barcode)
            }
            if isDescribeAvailable {
                Button("Describe") {
                    onAction(.describe)
                }
            }
            if isPhotoAvailable {
                Button("Photo") {
                    onAction(.photo)
                }
            }
            Button("Quick add") {
                onAction(.quickAdd)
            }
            Button("Saved meals") {
                onAction(.savedMeals)
            }
            Button("Alcohol") {
                onAction(.alcohol)
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(HelmColor.buttonPrimaryForeground)
                .frame(width: 36, height: 36)
                .background(HelmColor.buttonPrimaryBackground, in: Circle())
                .contentShape(Circle().inset(by: -4))
                .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
        }
        .buttonStyle(.helmPressable)
        .accessibilityLabel("Add food to \(bucket.displayName)")
    }
}

#Preview("Bucket add menu") {
    BucketFoodLogMenu(
        bucket: .lunch,
        isPhotoAvailable: true,
        onAction: { _ in }
    )
    .padding()
    .helmTheme()
}
