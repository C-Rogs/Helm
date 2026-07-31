import SwiftUI

public enum SetRowField: Hashable, Sendable {
    case weight
    case reps
    case rpe
}

public struct SetRow: View {
    public let setNumber: Int
    public let setTypeLabel: String?
    public let setTypeAccent: Color?
    public let setIndexAccessibilityLabel: String?
    public let weightState: SetRowFieldValueState
    public let repsState: SetRowFieldValueState
    public let rpeState: SetRowFieldValueState
    public let previousValue: String?
    public let isCompleted: Bool
    public let activeField: SetRowField?
    public let validationMessage: String?
    public let shakeToken: Int
    public let badgeText: String?
    public let onPreviousTap: (() -> Void)?
    public let onSetIndexTap: (() -> Void)?
    public let onFieldTap: (SetRowField) -> Void
    public let onComplete: () -> Void

    @Environment(\.helmReduceMotion) private var reduceMotion

    public init(
        setNumber: Int,
        setTypeLabel: String? = nil,
        setTypeAccent: Color? = nil,
        setIndexAccessibilityLabel: String? = nil,
        weightState: SetRowFieldValueState,
        repsState: SetRowFieldValueState,
        rpeState: SetRowFieldValueState,
        previousValue: String? = nil,
        isCompleted: Bool,
        activeField: SetRowField? = nil,
        validationMessage: String? = nil,
        shakeToken: Int = 0,
        badgeText: String? = nil,
        onPreviousTap: (() -> Void)? = nil,
        onSetIndexTap: (() -> Void)? = nil,
        onFieldTap: @escaping (SetRowField) -> Void,
        onComplete: @escaping () -> Void
    ) {
        self.setNumber = setNumber
        self.setTypeLabel = setTypeLabel
        self.setTypeAccent = setTypeAccent
        self.setIndexAccessibilityLabel = setIndexAccessibilityLabel
        self.weightState = weightState
        self.repsState = repsState
        self.rpeState = rpeState
        self.previousValue = previousValue
        self.isCompleted = isCompleted
        self.activeField = activeField
        self.validationMessage = validationMessage
        self.shakeToken = shakeToken
        self.badgeText = badgeText
        self.onPreviousTap = onPreviousTap
        self.onSetIndexTap = onSetIndexTap
        self.onFieldTap = onFieldTap
        self.onComplete = onComplete
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: HelmSpacing.xxs) {
            rowContent
            if let validationMessage {
                Text(validationMessage)
                    .helmType(.monoTag, color: HelmColor.destructive)
                    .padding(.horizontal, HelmSpacing.xs)
            }
        }
        .helmShake(trigger: shakeToken, reduceMotion: reduceMotion)
    }

    private var rowContent: some View {
        HStack(spacing: HelmSpacing.xs) {
            setIndexColumn

            previousColumn

            valueField(title: "kg", state: weightState, field: .weight)
            valueField(title: "reps", state: repsState, field: .reps)
            valueField(title: "RPE", state: rpeState, field: .rpe)
                .frame(width: 56)

            if let badgeText {
                Text(badgeText)
                    .helmType(.monoTag, color: HelmColor.accent)
                    .padding(.horizontal, HelmSpacing.xxs)
                    .padding(.vertical, 2)
                    .background(HelmColor.accent.opacity(0.15), in: Capsule())
            }

            Button(action: onComplete) {
                HelmIconView(isCompleted ? .checkmarkFilled : .circle, context: .inline)
                    .foregroundStyle(isCompleted ? HelmColor.accent : HelmColor.fgMuted)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.helmPressable)
            .accessibilityLabel(isCompleted ? "Mark set incomplete" : "Complete set")
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
    private var setIndexColumn: some View {
        let label = setTypeLabel ?? "\(setNumber)"
        let color = setTypeAccent ?? HelmColor.fgMuted
        Group {
            if let onSetIndexTap {
                Button(action: onSetIndexTap) {
                    Text(label)
                        .helmType(.monoTag, color: color)
                }
                .buttonStyle(.helmPressable)
                .accessibilityLabel(resolvedSetIndexAccessibilityLabel)
            } else {
                Text(label)
                    .helmType(.monoTag, color: color)
            }
        }
        .frame(width: 22, alignment: .leading)
    }

    private var resolvedSetIndexAccessibilityLabel: String {
        setIndexAccessibilityLabel ?? "Set \(setNumber), change set type"
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
        state: SetRowFieldValueState,
        field: SetRowField
    ) -> some View {
        let isActive = activeField == field
        let displayText = displayText(for: state)
        let textColor = SetRowFieldValueStateResolver.textColor(for: state)
        let showsCaret = SetRowFieldValueStateResolver.showsCaret(for: state)
        let showsSelection = SetRowFieldValueStateResolver.showsSelectionHighlight(for: state)

        return Button {
            onFieldTap(field)
        } label: {
            VStack(spacing: HelmSpacing.xxs) {
                Text(title)
                    .helmType(.monoTag, color: HelmColor.fgMuted)
                ZStack(alignment: .bottom) {
                    Text(displayText)
                        .helmType(.number, color: textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.horizontal, showsSelection ? HelmSpacing.xxs : 0)
                        .background {
                            if showsSelection {
                                HelmColor.accent.opacity(0.22)
                            }
                        }
                    if showsCaret {
                        Rectangle()
                            .fill(HelmColor.accent)
                            .frame(width: 2, height: 18)
                            .offset(x: caretOffset(for: displayText))
                    }
                }
                .overlay(alignment: .bottom) {
                    if isActive, !showsCaret, !showsSelection {
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
        .accessibilityLabel("\(title) \(displayText)")
    }

    private func displayText(for state: SetRowFieldValueState) -> String {
        switch state {
        case .prefilled(let display), .committed(let display), .editing(let display, _, _):
            display
        }
    }

    private func caretOffset(for text: String) -> CGFloat {
        CGFloat(text.count) * 5
    }
}

#Preview("Set row warmup") {
    SetRow(
        setNumber: 1,
        setTypeLabel: "W",
        setTypeAccent: HelmColor.fgSecondary,
        weightState: .committed(display: "40"),
        repsState: .committed(display: "10"),
        rpeState: .prefilled(display: "-"),
        previousValue: "40×10",
        isCompleted: false,
        onPreviousTap: {},
        onSetIndexTap: {},
        onFieldTap: { _ in },
        onComplete: {}
    )
    .padding()
    .helmTheme()
}

#Preview("Set row active") {
    SetRow(
        setNumber: 1,
        weightState: .editing(display: "80", showsCaret: true, isSelectAll: false),
        repsState: .prefilled(display: "8"),
        rpeState: .prefilled(display: "-"),
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
        weightState: .committed(display: "80"),
        repsState: .committed(display: "8"),
        rpeState: .committed(display: "8"),
        isCompleted: true,
        onFieldTap: { _ in },
        onComplete: {}
    )
    .padding()
    .helmTheme()
}
