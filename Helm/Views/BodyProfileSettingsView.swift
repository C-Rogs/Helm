import Core
import DesignSystem
import HealthKitIngest
import NutritionKit
import Persistence
import SwiftUI

struct BodyProfileEditorView: View {
    @Binding var profile: BodyProfile
    var showsTDEEPreview: Bool = true

    private var previewTDEE: Int? {
        guard profile.isComplete else { return nil }
        return BodyProfileTDEE.seedTDEEKcal(profile: profile).map { Int($0.rounded()) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.md) {
            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                Text("Weight (kg)")
                    .helmType(.label, color: HelmColor.fgSecondary)
                TextField("Weight", value: $profile.bodyMassKg, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                Text("Height (cm)")
                    .helmType(.label, color: HelmColor.fgSecondary)
                TextField("Height", value: $profile.heightCm, format: .number.precision(.fractionLength(0)))
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                Text("Sex")
                    .helmType(.label, color: HelmColor.fgSecondary)
                Picker("Sex", selection: $profile.biologicalSex) {
                    ForEach(BiologicalSex.allCases) { sex in
                        Text(sex.label).tag(sex)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                Text("Date of birth")
                    .helmType(.label, color: HelmColor.fgSecondary)
                DatePicker(
                    "Date of birth",
                    selection: $profile.dateOfBirth,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .labelsHidden()
                .datePickerStyle(.compact)
            }

            if showsTDEEPreview {
                tdeePreview
            }
        }
    }

    @ViewBuilder
    private var tdeePreview: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Estimated maintenance")
                .helmType(.label, color: HelmColor.fgSecondary)

            if let previewTDEE {
                HStack(alignment: .firstTextBaseline, spacing: HelmSpacing.xs) {
                    HelmNumericText(previewTDEE)
                        .helmType(.bigNumber)
                    Text("kcal / day")
                        .helmType(.body, color: HelmColor.fgMuted)
                }
                Text("Starting point for calorie targets. Helm refines this from your food logs and weight trend, not from diet calories alone during a cut.")
                    .helmType(.body, color: HelmColor.fgMuted)
            } else {
                Text("Enter weight, height, sex, and date of birth to calculate maintenance calories.")
                    .helmType(.body, color: HelmColor.fgMuted)
            }
        }
        .padding(HelmSpacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .helmPanelChrome(.surface)
    }
}

struct BodyProfileSettingsActions {
    let saveIfNeeded: () async -> Bool
    let isDirty: () -> Bool
    let isValid: () -> Bool
}

struct BodyProfileSettingsView: View {
    var embedInForm: Bool = true
    var showsInlineSaveButton: Bool = true
    var saveButtonTitle: String = "Save profile"
    var onSaved: (() -> Void)?
    var registerActions: ((BodyProfileSettingsActions) -> Void)?
    var onLoadingChanged: ((Bool) -> Void)?

    @State private var isLoading = true
    @State private var profile = BodyProfile(
        bodyMassKg: 70,
        heightCm: 170,
        biologicalSex: .male,
        dateOfBirth: Calendar.current.date(byAdding: .year, value: -30, to: Date()) ?? Date()
    )
    @State private var loadedProfile: BodyProfile?
    @State private var saveMessage: String?
    @State private var isSaving = false

    private var store: BodyProfileStore {
        BodyProfileStore(metadata: PersistenceBootstrap.persistenceStore.appMetadata)
    }

    private var isDirty: Bool {
        loadedProfile != profile
    }

    private var isValid: Bool {
        profile.isComplete && profile.ageYears() >= 13
    }

    var body: some View {
        Group {
            if embedInForm {
                Form { settingsContent }
            } else {
                settingsContent
            }
        }
        .navigationTitle("Body Profile")
        .helmScreenBackground()
        .scrollContentBackground(.hidden)
        .task { await load() }
        .onAppear {
            registerActions?(BodyProfileSettingsActions(
                saveIfNeeded: { await saveIfNeeded() },
                isDirty: { isDirty },
                isValid: { isValid }
            ))
        }
    }

    @ViewBuilder
    private var settingsContent: some View {
        if embedInForm {
            formSections
        } else {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                Text("Helm uses these metrics to set your starting maintenance calories and macro targets. Values from Apple Health are prefilled when available.")
                    .helmType(.body, color: HelmColor.fgSecondary)

                BodyProfileEditorView(profile: $profile)
                    .disabled(isLoading)

                if isLoading {
                    HStack(spacing: HelmSpacing.xs) {
                        ProgressView()
                        Text("Reading Apple Health…")
                            .helmType(.body, color: HelmColor.fgSecondary)
                    }
                }

                if let saveMessage {
                    Text(saveMessage)
                        .helmType(.body, color: HelmColor.depleted)
                }
            }
        }
    }

    @ViewBuilder
    private var formSections: some View {
        Section {
            Text("Helm uses these metrics for calorie targets and coach context. Weight updates from Apple Health when available.")
                .helmType(.body, color: HelmColor.fgSecondary)
        }

        Section("Metrics") {
            BodyProfileEditorView(profile: $profile)
                .disabled(isLoading)
        }

        if let saveMessage {
            Section {
                Text(saveMessage)
                    .foregroundStyle(HelmColor.fgSecondary)
            }
        }

        if showsInlineSaveButton {
            Section {
                HelmAsyncActionButton(saveButtonTitle, successTitle: "Saved") {
                    await save()
                }
                .disabled(isLoading || !isValid)
            }
        }
    }

    private func load() async {
        isLoading = true
        onLoadingChanged?(true)
        defer {
            isLoading = false
            onLoadingChanged?(false)
        }

        if let stored = store.load() {
            profile = stored
            loadedProfile = stored
            return
        }

        let prefill = await HealthKitBodyProfileReader().partialPrefill()
        if let mass = prefill.bodyMassKg {
            profile.bodyMassKg = mass
        }
        if let height = prefill.heightCm {
            profile.heightCm = height
        }
        if let sex = prefill.biologicalSex {
            profile.biologicalSex = sex
        }
        if let dob = prefill.dateOfBirth {
            profile.dateOfBirth = dob
        }
        loadedProfile = profile
    }

    @discardableResult
    private func saveIfNeeded() async -> Bool {
        guard isDirty else { return true }
        return await save()
    }

    @discardableResult
    private func save() async -> Bool {
        guard isValid else {
            saveMessage = "Enter a valid weight, height, sex, and date of birth."
            HapticEngine.shared.play(.clampRejected)
            return false
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try store.save(profile)
            loadedProfile = profile
            CloudBackupCoordinator.shared.schedulePush()
            saveMessage = "Body profile saved. Calorie targets will refresh."
            HapticEngine.shared.play(.selection)
            NutritionBootstrap.refreshNutrition()
            onSaved?()
            return true
        } catch {
            saveMessage = error.localizedDescription
            HapticEngine.shared.play(.clampRejected)
            return false
        }
    }
}

#Preview {
    NavigationStack {
        BodyProfileSettingsView()
    }
    .helmTheme()
}
