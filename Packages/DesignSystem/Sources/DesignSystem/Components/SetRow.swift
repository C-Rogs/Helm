import SwiftUI

public enum SetRowField: Hashable, Sendable {
    case weight
    case reps
    case rpe
}

public struct SetRow: View {
    public let setNumber: Int
    public let weight: String
    public let weightPlaceholder: String
    public let reps: String
    public let repsPlaceholder: String
    public let rpe: String
    public let rpePlaceholder: String
    public let previousValue: String?
    public let isCompleted: Bool
    public let activeField: SetRowField?
    public let onPreviousTap: (() -> Void)?
    public let onFieldTap: (SetRowField) -> Void
    public let onComplete: () -> Void

    @Environment(\.helmReduceMotion) private var reduceMotion

    public init(
        setNumber: Int,
        weight: String,
        weightPlaceholder: String = "-",
        reps: String,
        repsPlaceholder: String = "-",
        rpe: String,
        rpePlaceholder: String = "-",
        previousValue: String? = nil,
        isCompleted: Bool,
        activeField: SetRowField? = nil,
        onPreviousTap: (() -> Void)? = nil,
        onFieldTap: @escaping (SetRowField) -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.setNumber = setNumber
        self.weight = weight
        self.weightPlaceholder = weightPlaceholder
        self.reps = reps
        self.repsPlaceholder = repsPlaceholder
        self.rpe = rpe
        self.rpePlaceholder = rpePlaceholder
        self.previousValue = previousValue
        self.isCompleted = isCompleted
        self.activeField = activeField
        self.onPreviousTap = onPreviousTap
        self.onFieldTap = onFieldTap
        self.onComplete = onComplete
    }

    public var body: some View {
        HStack(spacing: HelmSpacing.xs) {
            Text("\(setNumber)")
                .helmType(.monoTag, color: HelmColor.fgMuted)
                .frame(width: 22, alignment: .leading)

            previousColumn

            valueField(title: "kg", value: weight, placeholder: weightPlaceholder, field: .weight)
            valueField(title: "reps", value: reps, placeholder: repsPlaceholder, field: .reps)
            valueField(title: "RPE", value: rpe, placeholder: rpePlaceholder, field: .rpe)
                .frame(width: 56)

            Button(action: onComplete) {
                HelmIconView(isCompleted ? .checkmarkFilled : .circle, context: .inline)
                    .foregroundStyle(isCompleted ? HelmColor.accent : HelmColor.fgMuted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.helmPressable)
            .accessibilityLabel(isCompleted ? "Set completed" : "Complete set")
        }
        .padding(.horizontal, HelmSpacing.xs)
        .padding(.vertical, HelmSpacing.xxs)
        .background(HelmColor.surfaceElevated.opacity(isCompleted ? 0.55 : 1), in: RoundedRectangle(cornerRadius: HelmRadius.sm))
        .overlay {
            RoundedRectangle(cornerRadius: HelmRadius.sm)
                .strokeBorder(borderColor, lineWidth: activeField == nil && !isCompleted ? 1 : 1.5)
        }
        .animation(HelmMotion.animation(HelmMotion.settleAnimation, reduceMotion: reduceMotion), value: isCompleted)
        .opacity(isCompleted ? 0.88 : 1)
    }

    private var borderColor: Color {
        if isCompleted { return HelmColor.accent.opacity(0.55) }
        if activeField != nil { return HelmColor.fg }
        return HelmColor.hairline
    }

    @ViewBuilder
    private var previousColumn: some View {
        if let previousValue, let onPreviousTap {
            Button(action: onPreviousTap) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PREV")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                    Text(previousValue)
                        .helmType(.number, color: HelmColor.fgSecondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.helmPressable)
        } else {
            Text("-")
                .helmType(.number, color: HelmColor.fgMuted)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func valueField(
        title: String,
        value: String,
        placeholder: String,
        field: SetRowField
    ) -> some View {
        let isActive = activeField == field
        return Button {
            onFieldTap(field)
        } label: {
            VStack(spacing: HelmSpacing.xxs) {
                Text(title)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                Text(value.isEmpty ? placeholder : value)
                    .helmType(.number, color: value.isEmpty ? HelmColor.fgMuted : HelmColor.fg)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .overlay(alignment: .bottom) {
                        if isActive {
                            Rectangle()
                                .fill(HelmColor.accent)
                                .frame(height: 2)
                                .offset(y: 4)
                        }
                    }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, HelmSpacing.xs)
        }
        .buttonStyle(.helmPressable)
        .accessibilityLabel("\(title) \(value.isEmpty ? placeholder : value)")
    }
}

#Preview("Set row active") {
    SetRow(
        setNumber: 1,
        weight: "80",
        reps: "8",
        rpe: "8",
        previousValue: "77.5×8",
        isCompleted: false,
        activeField: .weight,
        onPreviousTap: {},
        onFieldTap: { _ in },
        onComplete: {}
    )
    .padding()
    .helmTheme()
}

#Preview("Set row completed") {
    SetRow(
        setNumber: 2,
        weight: "80",
        reps: "8",
        rpe: "",
        isCompleted: true,
        onFieldTap: { _ in },
        onComplete: {}
    )
    .padding()
    .helmTheme()
}
