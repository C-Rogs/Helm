import DesignSystem
import SwiftUI
import Testing

@Suite("Set row field value state")
struct SetRowFieldValueStateTests {
    @Test("prefilled uses muted colour")
    func prefilledColour() {
        let state = SetRowFieldValueState.prefilled(display: "80")
        #expect(SetRowFieldValueStateResolver.textColor(for: state) == HelmColor.fgMuted)
    }

    @Test("committed uses primary colour")
    func committedColour() {
        let state = SetRowFieldValueState.committed(display: "80")
        #expect(SetRowFieldValueStateResolver.textColor(for: state) == HelmColor.fg)
    }

    @Test("editing committed tap uses select-all highlight")
    func editingSelectAll() {
        let state = SetRowFieldValueState.editing(display: "80", showsCaret: false, isSelectAll: true)
        #expect(SetRowFieldValueStateResolver.showsSelectionHighlight(for: state))
        #expect(!SetRowFieldValueStateResolver.showsCaret(for: state))
        #expect(SetRowFieldValueStateResolver.textColor(for: state) == HelmColor.fg)
    }

    @Test("editing prefilled tap shows caret")
    func editingCaret() {
        let state = SetRowFieldValueState.editing(display: "80", showsCaret: true, isSelectAll: false)
        #expect(SetRowFieldValueStateResolver.showsCaret(for: state))
        #expect(!SetRowFieldValueStateResolver.showsSelectionHighlight(for: state))
    }

    @Test("resolver returns prefilled when no stored value")
    func prefilledState() {
        let state = SetRowFieldValueStateResolver.resolve(
            hasStoredValue: false,
            displayText: "",
            prefilledText: "77.5",
            isCompleted: false,
            isActive: false,
            isSelectAll: false
        )
        #expect(state == .prefilled(display: "77.5"))
    }

    @Test("resolver returns committed when stored value exists")
    func committedState() {
        let state = SetRowFieldValueStateResolver.resolve(
            hasStoredValue: true,
            displayText: "80",
            prefilledText: "77.5",
            isCompleted: false,
            isActive: false,
            isSelectAll: false
        )
        #expect(state == .committed(display: "80"))
    }

    @Test("resolver returns committed when set is completed")
    func completedState() {
        let state = SetRowFieldValueStateResolver.resolve(
            hasStoredValue: false,
            displayText: "",
            prefilledText: "77.5",
            isCompleted: true,
            isActive: false,
            isSelectAll: false
        )
        #expect(state == .committed(display: "77.5"))
    }

    @Test("resolver returns editing with select-all for active prefilled field")
    func activePrefilledEditing() {
        let state = SetRowFieldValueStateResolver.resolve(
            hasStoredValue: false,
            displayText: "77.5",
            prefilledText: "77.5",
            isCompleted: false,
            isActive: true,
            isSelectAll: true
        )
        #expect(state == .editing(display: "77.5", showsCaret: false, isSelectAll: true))
        #expect(SetRowFieldValueStateResolver.showsSelectionHighlight(for: state))
    }

    @Test("resolver returns editing with select-all for active committed field")
    func activeCommittedEditing() {
        let state = SetRowFieldValueStateResolver.resolve(
            hasStoredValue: true,
            displayText: "80",
            prefilledText: "77.5",
            isCompleted: false,
            isActive: true,
            isSelectAll: true
        )
        #expect(state == .editing(display: "80", showsCaret: false, isSelectAll: true))
    }
}
