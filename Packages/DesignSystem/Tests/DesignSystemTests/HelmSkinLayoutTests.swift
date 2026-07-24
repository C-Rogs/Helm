import Foundation
import Testing
@testable import DesignSystem

@Suite("HelmSkin layout")
struct HelmSkinLayoutTests {
    @Test("selectable skins expose instrument and data sheet")
    func selectableSkins() {
        #expect(HelmSkin.selectableSkins == [.instrument, .dataSheet])
        #expect(HelmSkin.instrument.isSelectable)
        #expect(HelmSkin.dataSheet.isSelectable)
        #expect(!HelmSkin.stateField.isSelectable)
        #expect(!HelmSkin.blueprint.isSelectable)
    }

    @Test("data sheet tightens section spacing")
    func sectionSpacing() {
        #expect(HelmSkin.instrument.sectionSpacing == HelmSpacing.lg)
        #expect(HelmSkin.dataSheet.sectionSpacing == HelmSpacing.sm)
        #expect(HelmSkin.dataSheet.sectionSpacing < HelmSkin.instrument.sectionSpacing)
    }

    @Test("accent stripe is instrument only")
    func accentStripe() {
        #expect(HelmSkin.instrument.usesAccentStripe)
        #expect(!HelmSkin.dataSheet.usesAccentStripe)
    }

    @Test("theme coordinator falls back for reserved skins")
    @MainActor
    func coordinatorSkinFallback() {
        let defaults = UserDefaults(suiteName: "HelmSkinLayoutTests")!
        defaults.removePersistentDomain(forName: "HelmSkinLayoutTests")

        defaults.set(HelmSkin.blueprint.rawValue, forKey: "helm.skin")
        let coordinator = HelmThemeCoordinator(defaults: defaults)

        #expect(coordinator.skin == .instrument)

        coordinator.skin = .dataSheet
        #expect(defaults.string(forKey: "helm.skin") == HelmSkin.dataSheet.rawValue)
    }
}
