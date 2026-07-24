import Core
import DesignSystem
import SwiftUI

struct MealTemplatesSheet: View {
    let templates: [MealTemplate]
    let onLog: (MealTemplate) -> Void
    let onDelete: (MealTemplate) -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if templates.isEmpty {
                    ContentUnavailableView(
                        "No templates",
                        systemImage: "tray",
                        description: Text("Save a meal bucket as a template to log it in one tap.")
                    )
                } else {
                    List {
                        ForEach(templates) { template in
                            Button {
                                onLog(template)
                            } label: {
                                templateRow(template)
                            }
                            .buttonStyle(.helmPressable)
                            .listRowBackground(HelmColor.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete(template)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .helmScreenBackground()
            .navigationTitle("Meal templates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }

    private func templateRow(_ template: MealTemplate) -> some View {
        HStack(alignment: .top, spacing: HelmSpacing.sm) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text(template.name)
                    .helmType(.label)
                Text("\(template.bucket.displayName) · \(template.lineItems.count) items")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
            Spacer()
            Text("\(templateTotalKcal(template)) kcal")
                .helmType(.monoTag, color: HelmColor.fgMuted)
        }
        .padding(.vertical, HelmSpacing.xxs)
    }

    private func templateTotalKcal(_ template: MealTemplate) -> Int {
        Int(template.lineItems.reduce(0) { $0 + $1.caloriesKcal }.rounded())
    }
}

struct LogMealTemplateConfirmSheet: View {
    let template: MealTemplate
    let isSaving: Bool
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: HelmSpacing.lg) {
                VStack(alignment: .leading, spacing: HelmSpacing.xs) {
                    Text(template.name)
                        .helmType(.title)
                    Text("\(template.bucket.displayName) · \(template.lineItems.count) items")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                }

                VStack(alignment: .leading, spacing: HelmSpacing.sm) {
                    ForEach(template.lineItems) { item in
                        HStack {
                            Text(item.name)
                                .helmType(.body)
                            Spacer()
                            Text("\(Int(item.caloriesKcal.rounded())) kcal")
                                .helmType(.monoTag, color: HelmColor.fgMuted)
                        }
                    }
                }

                Spacer()
            }
            .padding(HelmSpacing.md)
            .helmScreenBackground()
            .navigationTitle("Log template")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button("Log template") {
                    onConfirm()
                }
                .buttonStyle(.helmPrimary)
                .disabled(isSaving)
                .padding(HelmSpacing.md)
                .background(HelmColor.surface.opacity(0.96))
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Templates list") {
    MealTemplatesSheet(
        templates: [
            MealTemplate(
                name: "Work breakfast",
                bucket: .breakfast,
                lineItems: [
                    MealLineItem(
                        name: "Oats",
                        grams: 60,
                        caloriesKcal: 230,
                        proteinG: 8,
                        carbsG: 40,
                        fatG: 4,
                        matchConfidence: .high
                    )
                ],
                updatedAt: Date()
            )
        ],
        onLog: { _ in },
        onDelete: { _ in },
        onDismiss: {}
    )
    .helmTheme()
}

#Preview("Log template confirm") {
    LogMealTemplateConfirmSheet(
        template: MealTemplate(
            name: "Work breakfast",
            bucket: .breakfast,
            lineItems: [
                MealLineItem(
                    name: "Oats",
                    grams: 60,
                    caloriesKcal: 230,
                    proteinG: 8,
                    carbsG: 40,
                    fatG: 4,
                    matchConfidence: .high
                )
            ],
            updatedAt: Date()
        ),
        isSaving: false,
        onConfirm: {},
        onCancel: {}
    )
    .helmTheme()
}
