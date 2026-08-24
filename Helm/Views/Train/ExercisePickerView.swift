import Core
import DesignSystem
import SwiftUI

/// Browse buckets for the exercise picker (muscle groups, not raw catalog muscles).
private enum ExercisePickerCategory: String, CaseIterable, Identifiable, Sendable {
    case chest
    case back
    case legs
    case shoulders
    case biceps
    case triceps
    case abs
    case olympic
    case fullBody

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chest: "Chest"
        case .back: "Back"
        case .legs: "Legs"
        case .shoulders: "Shoulders"
        case .biceps: "Biceps"
        case .triceps: "Triceps"
        case .abs: "Abs"
        case .olympic: "Olympic"
        case .fullBody: "Full Body"
        }
    }

    var systemImage: String {
        switch self {
        case .chest: "figure.strengthtraining.traditional"
        case .back: "figure.rower"
        case .legs: "figure.strengthtraining.functional"
        case .shoulders: "figure.boxing"
        case .biceps: "figure.arms.open"
        case .triceps: "figure.arms.above.head"
        case .abs: "figure.core.training"
        case .olympic: "figure.highintensity.intervaltraining"
        case .fullBody: "figure.mixed.cardio"
        }
    }

    var catalogMuscles: Set<String> {
        switch self {
        case .chest:
            ["chest"]
        case .back:
            ["lats", "upper back", "lower back", "traps", "middle back"]
        case .legs:
            ["quadriceps", "hamstrings", "glutes", "calves", "adductors", "abductors"]
        case .shoulders:
            ["shoulders"]
        case .biceps:
            ["biceps"]
        case .triceps:
            ["triceps"]
        case .abs:
            ["abs", "abdominals"]
        case .olympic, .fullBody:
            []
        }
    }

    static func category(for exercise: ExerciseSummary) -> ExercisePickerCategory? {
        let name = exercise.displayName.lowercased()
        if matchesOlympic(name) {
            return .olympic
        }
        if let muscle = exercise.primaryMuscleGroup?.lowercased() {
            for category in Self.allCases where !category.catalogMuscles.isEmpty {
                if category.catalogMuscles.contains(muscle) {
                    return category
                }
            }
        }
        if matchesFullBody(name) {
            return .fullBody
        }
        return nil
    }

    private static func matchesOlympic(_ name: String) -> Bool {
        let keys = [
            "snatch", "clean and jerk", "power clean", "hang clean", "power snatch",
            "hang snatch", "split jerk", "push jerk", "clean & jerk",
        ]
        return keys.contains { name.contains($0) }
    }

    private static func matchesFullBody(_ name: String) -> Bool {
        let keys = [
            "burpee", "thruster", "farmer", "turkish get", "kettlebell swing",
            "battle rope", "mountain climber", "jumping jack", "clean and press",
            "man maker", "wall ball",
        ]
        return keys.contains { name.contains($0) }
    }
}

struct ExercisePickerView: View {
    @Environment(\.dismiss) private var dismiss

    let fetchRecent: () throws -> [ExerciseSummary]
    let fetchExercises: (String, String?) throws -> [ExerciseSummary]
    let onSelect: (String) -> Void

    @State private var searchText = ""
    @State private var selectedCategory: ExercisePickerCategory?
    @State private var recentExercises: [ExerciseSummary] = []
    @State private var recentOrderIDs: [String] = []
    @State private var pickerDefaults: [ExerciseSummary] = []
    @State private var searchResults: [ExerciseSummary] = []
    @State private var loadError: String?

    private let recentPillLimit = 12

    private let columns = [
        GridItem(.flexible(), spacing: HelmSpacing.xs),
        GridItem(.flexible(), spacing: HelmSpacing.xs),
        GridItem(.flexible(), spacing: HelmSpacing.xs),
    ]

    var body: some View {
        NavigationStack {
            Group {
                if let loadError {
                    HelmErrorState(
                        title: "Exercises unavailable",
                        message: loadError,
                        onRetry: { reloadAll() }
                    )
                    .padding()
                } else {
                    content
                }
            }
            .helmScreenBackground()
            .navigationTitle("Select Exercise")
            .navigationBarTitleDisplayMode(.large)
            .searchable(text: $searchText, prompt: "Search exercises...")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 28))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(HelmColor.fgMuted)
                    }
                    .accessibilityLabel("Close")
                }
            }
            .onAppear { reloadAll() }
            .onChange(of: searchText) { _, _ in
                if !searchText.isEmpty {
                    selectedCategory = nil
                }
                reloadSearch()
            }
        }
        .helmTheme()
    }

    @ViewBuilder
    private var content: some View {
        if isSearching {
            searchResultsList
        } else if let category = selectedCategory {
            categoryExerciseList(category)
        } else {
            browseList
        }
    }

    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Browse

    private var browseList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HelmSpacing.md) {
                if !recentExercises.isEmpty {
                    recentSection
                }
                muscleGridSection
            }
            .padding(.horizontal, HelmSpacing.screenGutter)
            .padding(.bottom, HelmSpacing.xl)
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            sectionEyebrow(title: "Recently Used", systemImage: "clock")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: HelmSpacing.xs) {
                    ForEach(recentExercises) { exercise in
                        recentPill(exercise)
                    }
                }
            }
        }
    }

    private var muscleGridSection: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            sectionEyebrow(title: "Browse by Muscle", systemImage: "square.grid.2x2")

            LazyVGrid(columns: columns, spacing: HelmSpacing.xs) {
                ForEach(ExercisePickerCategory.allCases) { category in
                    let count = count(for: category)
                    muscleGroupTile(category, count: count)
                        .opacity(count == 0 ? 0.45 : 1)
                        .disabled(count == 0)
                }
            }
        }
    }

    private func sectionEyebrow(title: String, systemImage: String) -> some View {
        HStack(spacing: HelmSpacing.xxs) {
            Image(systemName: systemImage)
                .font(.system(size: 11, weight: .semibold))
            Text(title)
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
    }

    private func recentPill(_ exercise: ExerciseSummary) -> some View {
        Button {
            onSelect(exercise.id)
            dismiss()
        } label: {
            Text(exercise.displayName)
                .helmFont(.body)
                .foregroundStyle(HelmColor.accent)
                .lineLimit(1)
                .padding(.horizontal, HelmSpacing.sm)
                .padding(.vertical, HelmSpacing.xs)
                .overlay {
                    Capsule()
                        .strokeBorder(HelmColor.accent.opacity(0.55), lineWidth: 1)
                }
        }
        .buttonStyle(.helmPressable)
    }

    private func muscleGroupTile(_ category: ExercisePickerCategory, count: Int) -> some View {
        Button {
            selectedCategory = category
        } label: {
            VStack(spacing: HelmSpacing.xxs) {
                ZStack {
                    Circle()
                        .fill(HelmColor.surfaceElevated)
                        .frame(width: 36, height: 36)
                    Image(systemName: category.systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(HelmColor.accent)
                }
                .contentShape(Rectangle())

                Text(category.title)
                    .helmFont(.body)
                    .fontWeight(.semibold)
                    .foregroundStyle(HelmColor.textPrimary)
                    .lineLimit(1)

                Text("\(count) exercises")
                    .helmFont(.body)
                    .foregroundStyle(HelmColor.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HelmSpacing.sm)
            .padding(.horizontal, HelmSpacing.xxs)
            .background(HelmColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: HelmRadius.md))
            .overlay {
                RoundedRectangle(cornerRadius: HelmRadius.md)
                    .strokeBorder(HelmColor.hairline, lineWidth: 1)
            }
        }
        .buttonStyle(.helmPressable)
        .accessibilityLabel("\(category.title), \(count) exercises")
    }

    // MARK: - Category list

    private func categoryExerciseList(_ category: ExercisePickerCategory) -> some View {
        List {
            Section {
                ForEach(exercises(in: category)) { exercise in
                    exerciseListRow(exercise)
                }
            } header: {
                Button {
                    selectedCategory = nil
                } label: {
                    HStack(spacing: HelmSpacing.xxs) {
                        Image(systemName: "chevron.left")
                        Text("All muscles")
                    }
                    .helmFont(.body)
                    .foregroundStyle(HelmColor.accent)
                }
                .buttonStyle(.plain)
                .textCase(nil)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .navigationTitle(category.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Search

    private var searchResultsList: some View {
        List {
            if searchResults.isEmpty {
                ContentUnavailableView(
                    "No results",
                    systemImage: "magnifyingglass",
                    description: Text("Try a different name or alias.")
                )
            } else {
                ForEach(searchResults) { exercise in
                    exerciseListRow(exercise)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func exerciseListRow(_ exercise: ExerciseSummary) -> some View {
        Button {
            onSelect(exercise.id)
            dismiss()
        } label: {
            HStack(spacing: HelmSpacing.sm) {
                exerciseThumb(urlString: exercise.gifURL, size: 44)

                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text(exercise.displayName)
                        .helmFont(.body)
                        .fontWeight(.semibold)
                        .foregroundStyle(HelmColor.textPrimary)
                    if let muscle = exercise.primaryMuscleGroup {
                        Text(muscle.capitalized)
                            .helmFont(.body)
                            .foregroundStyle(HelmColor.textSecondary)
                    }
                }
            }
            .padding(.vertical, HelmSpacing.xxs)
        }
    }

    private func exerciseThumb(urlString: String?, size: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: HelmRadius.sm)
                .fill(HelmColor.surface)
                .frame(width: size, height: size)

            if let urlString, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: HelmRadius.sm))
                    case .failure, .empty:
                        Image(systemName: "dumbbell")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(HelmColor.textSecondary)
                    @unknown default:
                        Image(systemName: "dumbbell")
                            .font(.system(size: size * 0.4))
                            .foregroundStyle(HelmColor.textSecondary)
                    }
                }
                .frame(width: size - 4, height: size - 4)
            } else {
                Image(systemName: "dumbbell")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(HelmColor.textSecondary)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.sm)
                .strokeBorder(HelmColor.hairline, lineWidth: 1)
        }
    }

    // MARK: - Data

    private func count(for category: ExercisePickerCategory) -> Int {
        exercises(in: category).count
    }

    private func exercises(in category: ExercisePickerCategory) -> [ExerciseSummary] {
        pickerDefaults
            .filter { ExercisePickerCategory.category(for: $0) == category }
            .sorted { lhs, rhs in
                let leftRank = recentOrderIDs.firstIndex(of: lhs.id) ?? Int.max
                let rightRank = recentOrderIDs.firstIndex(of: rhs.id) ?? Int.max
                if leftRank != rightRank {
                    return leftRank < rightRank
                }
                return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
            }
    }

    private func reloadAll() {
        do {
            let allRecent = try fetchRecent()
            recentOrderIDs = allRecent.map(\.id)
            recentExercises = Array(allRecent.prefix(recentPillLimit))
            pickerDefaults = try fetchExercises("", nil)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func reloadSearch() {
        guard isSearching else {
            searchResults = []
            return
        }
        do {
            searchResults = try fetchExercises(searchText, nil)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

#Preview("Exercise picker - browse") {
    ExercisePickerView(
        fetchRecent: {
            [
                ExerciseSummary(
                    id: "1",
                    displayName: "Bench Press (Barbell)",
                    exerciseMode: .weightReps,
                    isCustom: false,
                    primaryMuscleGroup: "chest"
                )
            ]
        },
        fetchExercises: { _, _ in
            [
                ExerciseSummary(
                    id: "1",
                    displayName: "Bench Press (Barbell)",
                    exerciseMode: .weightReps,
                    isCustom: false,
                    primaryMuscleGroup: "chest"
                ),
                ExerciseSummary(
                    id: "2",
                    displayName: "Squat (Barbell)",
                    exerciseMode: .weightReps,
                    isCustom: false,
                    primaryMuscleGroup: "quadriceps"
                ),
                ExerciseSummary(
                    id: "3",
                    displayName: "Pull Up",
                    exerciseMode: .bodyweightReps,
                    isCustom: false,
                    primaryMuscleGroup: "lats"
                ),
            ]
        },
        onSelect: { _ in }
    )
}