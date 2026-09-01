import Foundation
import Testing
@testable import DesignSystem

@Suite("HelmSkin layout")
struct HelmSkinLayoutTests {
    @Test("selectable skins expose signal, instrument, and data sheet")
    func selectableSkins() {
        #expect(HelmSkin.selectableSkins == [.signal, .instrument, .dataSheet])
        #expect(HelmSkin.signal.isSelectable)
        #expect(HelmSkin.instrument.isSelectable)
        #expect(HelmSkin.dataSheet.isSelectable)
        #expect(!HelmSkin.stateField.isSelectable)
        #expect(!HelmSkin.blueprint.isSelectable)
    }

    @Test("signal and data sheet tighten section spacing vs instrument")
    func sectionSpacing() {
        #expect(HelmSkin.signal.sectionSpacing == HelmSpacing.md)
        #expect(HelmSkin.instrument.sectionSpacing == HelmSpacing.lg)
        #expect(HelmSkin.dataSheet.sectionSpacing == HelmSpacing.sm)
        #expect(HelmSkin.signal.sectionSpacing < HelmSkin.instrument.sectionSpacing)
        #expect(HelmSkin.dataSheet.sectionSpacing < HelmSkin.signal.sectionSpacing)
    }

    @Test("accent stripe is instrument only")
    func accentStripe() {
        #expect(HelmSkin.instrument.usesAccentStripe)
        #expect(!HelmSkin.signal.usesAccentStripe)
        #expect(!HelmSkin.dataSheet.usesAccentStripe)
    }

    @Test("signal uses quieter press and staggered appear")
    func signalMotionHints() {
        #expect(HelmSkin.signal.pressScale == 0.97)
        #expect(HelmSkin.instrument.pressScale == 0.96)
        #expect(HelmSkin.signal.pressScale > HelmSkin.instrument.pressScale)
        #expect(HelmSkin.signal.usesStaggeredAppear)
        #expect(!HelmSkin.instrument.usesStaggeredAppear)
    }

    @Test("theme coordinator defaults to signal and falls back for reserved skins")
    @MainActor
    func coordinatorSkinFallback() {
        let defaults = UserDefaults(suiteName: "HelmSkinLayoutTests")!
        defaults.removePersistentDomain(forName: "HelmSkinLayoutTests")

        let fresh = HelmThemeCoordinator(defaults: defaults)
        #expect(fresh.skin == .signal)

        defaults.set(HelmSkin.blueprint.rawValue, forKey: "helm.skin")
        let coordinator = HelmThemeCoordinator(defaults: defaults)
        #expect(coordinator.skin == .signal)

        coordinator.skin = .dataSheet
        #expect(defaults.string(forKey: "helm.skin") == HelmSkin.dataSheet.rawValue)

        coordinator.skin = .signal
        #expect(defaults.string(forKey: "helm.skin") == HelmSkin.signal.rawValue)
    }
}
