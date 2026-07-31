import SwiftUI

public enum SetRowFieldValueState: Equatable, Sendable {
    case prefilled(display: String)
    case committed(display: String)
    case editing(display: String, showsCaret: Bool, isSelectAll: Bool)
}

public enum SetRowFieldValueStateResolver {
    public static func resolve(
        hasStoredValue: Bool,
        displayText: String,
        prefilledText: String?,
        isCompleted: Bool,
        isActive: Bool,
        isSelectAll: Bool
    ) -> SetRowFieldValueState {
        let fallback = prefilledText ?? "-"
        let visible = displayText.isEmpty ? fallback : displayText

        if isActive {
            let editingDisplay = displayText.isEmpty ? fallback : displayText
            return .editing(
                display: editingDisplay,
                showsCaret: !isSelectAll,
                isSelectAll: isSelectAll
            )
        }

        if hasStoredValue || isCompleted {
            return .committed(display: visible)
        }

        if let prefilledText, prefilledText != "-" {
            return .prefilled(display: prefilledText)
        }

        return .prefilled(display: visible)
    }

    public static func textColor(for state: SetRowFieldValueState) -> Color {
        switch state {
        case .prefilled:
            HelmColor.fgMuted
        case .committed, .editing:
            HelmColor.fg
        }
    }

    public static func showsSelectionHighlight(for state: SetRowFieldValueState) -> Bool {
        if case .editing(_, _, let isSelectAll) = state {
            return isSelectAll
        }
        return false
    }

    public static func showsCaret(for state: SetRowFieldValueState) -> Bool {
        if case .editing(_, let showsCaret, _) = state {
            return showsCaret
        }
        return false
    }
}
