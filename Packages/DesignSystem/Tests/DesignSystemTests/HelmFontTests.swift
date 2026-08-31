import Testing
import UIKit
@testable import DesignSystem

@Suite("Helm fonts")
struct HelmFontTests {
    @Test("missing PostScript name is not registered")
    func missingFaceIsNotRegistered() {
        #expect(!HelmFont.isRegistered(postScriptName: "HelmMissingFace-Regular"))
    }

    @Test("system UIFont name is registered")
    func systemFaceIsRegistered() {
        let name = UIFont.systemFont(ofSize: 12).fontName
        #expect(HelmFont.isRegistered(postScriptName: name))
    }

    @Test("reregister is idempotent")
    func reregisterDoesNotThrow() {
        HelmFontRegistration.registerFontsIfNeeded()
        HelmFontRegistration.reregister()
        HelmFontRegistration.reregister()
    }
}

