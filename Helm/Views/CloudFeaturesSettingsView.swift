import DesignSystem
import SwiftUI

struct CloudFeaturesSettingsView: View {
    @Bindable private var consent = CloudFeatureConsentPreferences.shared

    var body: some View {
        List {
            Section {
                Toggle("Allow cloud features", isOn: $consent.isConsented)
                    .helmListRowChrome()
                    .onChange(of: consent.isConsented) { _, _ in
                        CoachBootstrap.start()
                        NutritionBootstrap.invalidatePhotoMealServiceCache()
                        HapticEngine.shared.play(.selection)
                    }
            } footer: {
                Text("When on, Coach sends a summary of your health, training, nutrition, body data, and coach memory to its provider. Meal photos and notes go to the meal-vision provider. Calendar event titles can go to Coach. Feedback goes to Cam, with coach history only when you choose to attach it.")
                    .helmType(.body, color: HelmColor.fgMuted)
            }

            Section {
                Text("Health import, workout logging, manual meal logging, and exports stay on this device whether cloud features are on or off.")
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .helmListRowChrome()
            }
        }
        .helmSettingsListChrome()
        .navigationTitle("Cloud features")
    }
}

#Preview {
    NavigationStack {
        CloudFeaturesSettingsView()
    }
    .helmTheme()
}
