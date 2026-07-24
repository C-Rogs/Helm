import DesignSystem
import HealthKitIngest
import SwiftUI

struct NutritionSettingsView: View {
    @State private var dietarySourceMode: DietarySourceMode

    private let preferences: NutritionPreferencesStore

    init(preferences: NutritionPreferencesStore = .shared) {
        self.preferences = preferences
        _dietarySourceMode = State(initialValue: preferences.mode())
    }

    var body: some View {
        List {
            Section {
                Picker("Dietary sources", selection: $dietarySourceMode) {
                    ForEach(DietarySourceMode.allCases, id: \.self) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: dietarySourceMode) { _, newValue in
                    preferences.setMode(newValue)
                    HapticEngine.shared.play(.selection)
                }

                Text(dietarySourceHelp)
                    .helmType(.body, color: HelmColor.fgMuted)
                    .fixedSize(horizontal: false, vertical: true)
            } header: {
                Text("Nutrition")
            }
        }
        .listStyle(.plain)
        .listRowBackground(HelmColor.surface)
        .navigationTitle("Nutrition")
        .helmScreenBackground()
    }

    private var dietarySourceHelp: String {
        switch dietarySourceMode {
        case .mergeExternal:
            "During the MyFitnessPal transition, Helm merges external HealthKit calories and deduplicates overlapping entries."
        case .helmOnly:
            "Only meals logged in Helm count toward intake. External dietary sources are ignored."
        }
    }
}

#Preview("Nutrition settings") {
    NavigationStack {
        NutritionSettingsView(
            preferences: NutritionPreferencesStore(defaults: UserDefaults(suiteName: "preview.nutrition.settings")!)
        )
    }
    .helmTheme()
}
