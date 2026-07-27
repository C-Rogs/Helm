import DesignSystem
import SwiftUI

struct NutritionFoodLogFAB: View {
    @Binding var isExpanded: Bool
    let isPhotoAvailable: Bool
    let onSearch: () -> Void
    let onBarcode: () -> Void
    let onPhoto: () -> Void
    let onQuickAdd: () -> Void
    let onAlcohol: () -> Void
    let onLogTemplate: () -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: HelmSpacing.sm) {
            if isExpanded {
                actionButton(label: "Search", icon: .search, action: onSearch)
                actionButton(label: "Barcode", icon: .barcode, action: onBarcode)
                actionButton(label: "Template", icon: .nutrition, action: onLogTemplate)
                if isPhotoAvailable {
                    actionButton(label: "Photo", icon: .photo, action: onPhoto)
                }
                actionButton(label: "Quick add", icon: .scale, action: onQuickAdd)
                actionButton(label: "Alcohol", icon: .nutrition, action: onAlcohol)
            }

            Button {
                withAnimation(.easeInOut(duration: 0.28)) {
                    isExpanded.toggle()
                }
                HapticEngine.shared.play(.selection)
            } label: {
                Image(systemName: isExpanded ? "xmark" : "plus")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(HelmColor.buttonPrimaryForeground)
                    .frame(width: 56, height: 56)
                    .background(HelmColor.buttonPrimaryBackground, in: Circle())
                    .shadow(color: .black.opacity(0.25), radius: 8, y: 4)
            }
            .buttonStyle(.helmPressable)
            .accessibilityLabel(isExpanded ? "Close food log actions" : "Log food")
        }
    }

    private func actionButton(label: String, icon: HelmIcon, action: @escaping () -> Void) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded = false
            }
            HapticEngine.shared.play(.selection)
            action()
        } label: {
            HStack(spacing: HelmSpacing.sm) {
                Text(label)
                    .helmType(.label)
                    .foregroundStyle(HelmColor.fg)
                    .padding(.horizontal, HelmSpacing.sm)
                    .padding(.vertical, HelmSpacing.xs)
                    .background(HelmColor.surface, in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(HelmColor.hairline, lineWidth: 1)
                    }

                HelmIconView(icon, context: .section)
                    .foregroundStyle(HelmColor.buttonPrimaryForeground)
                    .frame(width: 44, height: 44)
                    .background(HelmColor.surfaceElevated, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(HelmColor.hairline, lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.helmPressable)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

#Preview("FAB collapsed") {
    ZStack(alignment: .bottomTrailing) {
        Color.black.ignoresSafeArea()
        NutritionFoodLogFAB(
            isExpanded: .constant(false),
            isPhotoAvailable: true,
            onSearch: {},
            onBarcode: {},
            onPhoto: {},
            onQuickAdd: {},
            onAlcohol: {},
            onLogTemplate: {}
        )
        .padding(HelmSpacing.lg)
    }
    .helmTheme()
}

#Preview("FAB expanded") {
    ZStack(alignment: .bottomTrailing) {
        Color.black.ignoresSafeArea()
        NutritionFoodLogFAB(
            isExpanded: .constant(true),
            isPhotoAvailable: true,
            onSearch: {},
            onBarcode: {},
            onPhoto: {},
            onQuickAdd: {},
            onAlcohol: {},
            onLogTemplate: {}
        )
        .padding(HelmSpacing.lg)
    }
    .helmTheme()
}
