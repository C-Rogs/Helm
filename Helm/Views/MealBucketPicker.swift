import Core
import DesignSystem
import SwiftUI

struct MealBucketPicker: View {
    @Binding var selection: MealBucket
    var labelStyle: LabelStyle = .standard

    enum LabelStyle {
        case standard
        case muted
    }

    var body: some View {
        VStack(alignment: .leading, spacing: labelSpacing) {
            switch labelStyle {
            case .standard:
                Text("Meal")
                    .helmType(.label)
            case .muted:
                Text("Meal")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }

            Picker("Meal", selection: $selection) {
                ForEach(MealBucket.allCases, id: \.self) { mealBucket in
                    Text(mealBucket.displayName).tag(mealBucket)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var labelSpacing: CGFloat {
        switch labelStyle {
        case .standard:
            HelmSpacing.sm
        case .muted:
            HelmSpacing.xs
        }
    }
}
