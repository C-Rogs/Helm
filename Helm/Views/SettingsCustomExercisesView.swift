import Core
import DesignSystem
import Persistence
import SwiftUI

@MainActor
@Observable
final class CustomExercisesController {
    private let store: PersistenceStore

    private(set) var exercises: [ExerciseSummary] = []
    var errorMessage: String?

    init(store: PersistenceStore = PersistenceBootstrap.persistenceStore) {
        self.store = store
    }

    func reload() {
        do {
            exercises = try store.exercises.fetchCustomExercises()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addExercise(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let id = "custom-\(trimmed.lowercased().replacingOccurrences(of: " ", with: "-"))-\(Int(Date().timeIntervalSince1970))"
        do {
            try store.exercises.upsert(
                id: id,
                canonicalName: trimmed.lowercased(),
                displayName: trimmed,
                exerciseMode: .weightReps,
                isCustom: true,
                isPickerDefault: true
            )
            try store.exercises.addAlias(id: "alias-\(id)", exerciseID: id, alias: trimmed)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(_ exercise: ExerciseSummary, to newName: String) {
        do {
            try store.exercises.renameCustom(id: exercise.id, displayName: newName)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Returns false when the exercise is referenced by logged sessions.
    func delete(_ exercise: ExerciseSummary) -> Bool {
        do {
            if try store.exercises.isExerciseInUse(exercise.id) {
                errorMessage = "\(exercise.displayName) has logged sessions and cannot be deleted."
                return false
            }
            try store.exercises.softDelete(id: exercise.id)
            reload()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}

struct SettingsCustomExercisesView: View {
    @State private var controller = CustomExercisesController()
    @State private var newExerciseName = ""
    @State private var renamingExercise: ExerciseSummary?
    @State private var renameText = ""
    @State private var deleteCandidate: ExerciseSummary?
    @FocusState private var isNewNameFocused: Bool

    var body: some View {
        List {
            addSection
            customListSection
            if let message = controller.errorMessage {
                Text(message)
                    .helmType(.body, color: HelmColor.destructive)
                    .helmListRowChrome()
            }
        }
        .helmSettingsListChrome()
        .navigationTitle("Custom Exercises")
        .onAppear { controller.reload() }
        .alert(
            "Delete exercise?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } }
            )
        ) {
            Button("Delete", role: .destructive) {
                if let exercise = deleteCandidate {
                    _ = controller.delete(exercise)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(deleteCandidate?.displayName ?? "This exercise") will be removed from the catalogue.")
        }
        .alert(
            "Rename exercise",
            isPresented: Binding(
                get: { renamingExercise != nil },
                set: { if !$0 { renamingExercise = nil } }
            )
        ) {
            TextField("Name", text: $renameText)
            Button("Save") {
                if let exercise = renamingExercise {
                    controller.rename(exercise, to: renameText)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var addSection: some View {
        Section {
            HStack {
                TextField("New exercise name", text: $newExerciseName)
                    .focused($isNewNameFocused)
                    .onSubmit(addTapped)
                Button(action: addTapped) {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 24))
                        .foregroundStyle(HelmColor.accent)
                }
                .disabled(newExerciseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .helmListRowChrome()
        } header: {
            Text("Add")
        } footer: {
            Text("Custom exercises appear in search everywhere the coach resolves exercise names. The catalogue already includes every exercise from your training history, so add one only for genuinely new equipment.")
                .helmType(.body, color: HelmColor.fgMuted)
        }
    }

    private var customListSection: some View {
        Section("Your custom exercises") {
            if controller.exercises.isEmpty {
                Text("No custom exercises yet.")
                    .helmType(.body, color: HelmColor.fgMuted)
                    .helmListRowChrome()
            } else {
                ForEach(controller.exercises) { exercise in
                    HStack {
                        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                            Text(exercise.displayName)
                                .helmType(.body)
                            if let muscle = exercise.primaryMuscleGroup {
                                Text(muscle.capitalized)
                                    .helmType(.body, color: HelmColor.fgMuted)
                            }
                        }
                        Spacer(minLength: HelmSpacing.sm)
                        Button {
                            renameText = exercise.displayName
                            renamingExercise = exercise
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundStyle(HelmColor.accent)
                        }
                        .buttonStyle(.borderless)

                        Button {
                            deleteCandidate = exercise
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(HelmColor.destructive)
                        }
                        .buttonStyle(.borderless)
                    }
                    .helmListRowChrome()
                }
            }
        }
    }

    private func addTapped() {
        controller.addExercise(named: newExerciseName)
        newExerciseName = ""
        isNewNameFocused = false
    }
}

#Preview("Custom exercises") {
    NavigationStack {
        SettingsCustomExercisesView()
    }
    .helmTheme()
}
