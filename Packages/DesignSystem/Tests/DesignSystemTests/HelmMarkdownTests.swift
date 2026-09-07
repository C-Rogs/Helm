import DesignSystem
import Testing

@Suite("HelmMarkdown")
struct HelmMarkdownTests {
    @Test("inline bold markers become presentation intent")
    func boldMarkersRenderAsIntent() {
        let attributed = HelmMarkdown.attributed("Try **incline** press")
        let plain = String(attributed.characters)
        #expect(plain == "Try incline press")
        #expect(!plain.contains("**"))

        var sawStrong = false
        for run in attributed.runs {
            if run.inlinePresentationIntent?.contains(.stronglyEmphasized) == true {
                sawStrong = true
                break
            }
        }
        #expect(sawStrong)
    }

    @Test("invalid markdown falls back to plain text")
    func invalidMarkdownFallsBack() {
        let raw = "Stay at 80 kg"
        let attributed = HelmMarkdown.attributed(raw)
        #expect(String(attributed.characters) == raw)
    }
}
