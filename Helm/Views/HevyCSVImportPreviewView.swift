import DesignSystem
import Persistence
import SwiftUI

struct HevyCSVImportPreviewView: View {
    @Bindable var controller: TrainingHistoryTransferController
    @State private var mappingExerciseTitle: String?
    @State private var isImporting = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: HelmSpacing.md) {
                    if let result = controller.hevyParseResult {
                        Card {
                            VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                                Text("\(result.sessions.count) sessions · \(result.totalSetCount) sets")
                                    .helmType(.body)
                                if let range = result.dateRange {
                                    Text("\(Self.dayFormatter.string(from: range.lowerBound)) – \(Self.dayFormatter.string(from: range.upperBound))")
                                        .helmType(.body, color: HelmColor.fgSecondary)
                                }
                                if result.clippedAwaySessionCount > 0 {
                                    Text("Clipped \(result.clippedAwaySessionCount) sessions older than 90 days.")
                                        .helmType(.body, color: HelmColor.warning)
                                }
                                if result.skippedCardioSetCount > 0 {
                                    Text("Skipped \(result.skippedCardioSetCount) cardio/duration rows without reps.")
                                        .helmType(.body, color: HelmColor.fgSecondary)
                                }
                            }
                        }
                    }

                    Text("Exercises")
                        .helmType(.label)

                    Card {
                        VStack(spacing: 0) {
                            ForEach(controller.hevyResolutions) { resolution in
                                HelmRuledRow {
                                    exerciseRow(resolution)
                                }
                            }
                        }
                    }

                    if let errorMessage = controller.errorMessage {
                        Text(errorMessage)
                            .helmFont(.body)
                            .foregroundStyle(HelmColor.destructive)
                    }

                    Button(isImporting || controller.isImportingHevy ? "Importing…" : "Import history") {
                        isImporting = true
                        defer { isImporting = false }
                        controller.confirmHevyImport()
                    }
                    .buttonStyle(.helmPrimary)
                    .disabled(!controller.canConfirmHevyImport || isImporting || controller.isImportingHevy)
                }
                .helmScreenPadding()
            }
            .helmScreenBackground()
            .navigationTitle("Hevy import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        controller.isShowingHevyPreview = false
                    }
                }
            }
            .sheet(isPresented: mappingSheetPresented) {
                if let title = mappingExerciseTitle {
                    ExercisePickerView(
                        fetchRecent: { try controller.fetchRecentExercises(limit: 500) },
                        fetchExercises: controller.fetchPickerExercises(search:muscleGroup:),
                        onSelect: { exerciseID in
                            controller.mapHevyExercise(importedTitle: title, to: exerciseID)
                            mappingExerciseTitle = nil
                        }
                    )
                }
            }
        }
        .helmTheme()
    }

    private var mappingSheetPresented: Binding<Bool> {
        Binding(
            get: { mappingExerciseTitle != nil },
            set: { if !$0 { mappingExerciseTitle = nil } }
        )
    }

    @ViewBuilder
    private func exerciseRow(_ resolution: WorkoutImportExerciseResolution) -> some View {
        VStack(alignment: .leading, spacing: HelmSpacing.sm) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                    Text(resolution.importedTitle)
                        .helmType(.body)
                    if let exerciseID = resolution.exerciseID {
                        Text(controller.displayName(for: exerciseID))
                            .helmType(.body, color: HelmColor.fgSecondary)
                    }
                }
                Spacer(minLength: HelmSpacing.sm)
                matchBadge(for: resolution.matchKind)
            }

            Button(resolution.isResolved ? "Remap" : "Map exercise") {
                mappingExerciseTitle = resolution.importedTitle
            }
            .buttonStyle(.helmSecondary)
        }
        .padding(.vertical, HelmSpacing.xs)
    }

    private func matchBadge(for kind: WorkoutImportMatchKind) -> some View {
        switch kind {
        case .alias, .displayName, .manual:
            statusBadge(label: kind == .manual ? "Mapped" : "Matched", color: HelmColor.positive)
        case .unresolved:
            statusBadge(label: "Map", color: HelmColor.warning)
        }
    }

    private func statusBadge(label: String, color: Color) -> some View {
        Text(label)
            .helmFont(.body)
            .foregroundStyle(color)
            .padding(.horizontal, HelmSpacing.xs)
            .padding(.vertical, HelmSpacing.xxs)
            .background(color.opacity(0.15))
            .clipShape(Capsule())
    }

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
