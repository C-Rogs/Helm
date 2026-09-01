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
                        "No saved meals",
                        systemImage: "tray",
                        description: Text("Save a meal bucket as a template, then log it from + on any meal.")
                    )
                } else {
                    List {
                        ForEach(templates) { template in
                            Button {
                                onLog(template)
                            } label: {
                                templateRow(template)
                            }
                            .buttonStyle(.plain)
                            .contentShape(Rectangle())
                            .listRowBackground(HelmColor.surface)
                            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                Button(role: .destructive) {
                                    onDelete(template)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            .accessibilityLabel("Log \(template.name)")
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .helmScreenBackground()
            .navigationTitle("Saved meals")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDismiss)
                }
            }
        }
    }

    private func templateRow(_ template: MealTemplate) -> some View {
        HStack(alignment: .center, spacing: HelmSpacing.sm) {
            VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
                Text(template.name)
                    .helmType(.label)
                    .foregroundStyle(HelmColor.fg)
                Text("\(template.bucket.displayName) · \(template.lineItems.count) items · \(templateTotalKcal(template)) kcal")
                    .helmType(.monoTag, color: HelmColor.fgMuted)
            }
            Spacer(minLength: HelmSpacing.sm)
            Text("Log")
                .helmType(.label, color: HelmColor.accent)
                .padding(.horizontal, HelmSpacing.sm)
                .padding(.vertical, HelmSpacing.xs)
                .background(HelmColor.gaugeTrack.opacity(0.35), in: Capsule())
        }
        .padding(.vertical, HelmSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func templateTotalKcal(_ template: MealTemplate) -> Int {
        Int(template.lineItems.reduce(0) { $0 + $1.caloriesKcal }.rounded())
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
