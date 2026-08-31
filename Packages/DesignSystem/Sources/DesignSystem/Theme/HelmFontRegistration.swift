import CoreText
import Foundation

public enum HelmFontRegistration {
    nonisolated(unsafe) private static var didRegister = false

    public static func registerFontsIfNeeded() {
        guard !didRegister else { return }
        registerAll()
        didRegister = true
    }

    /// Re-install process-scoped fonts after foreground. Safe if already registered.
    public static func reregister() {
        registerAll()
        didRegister = true
    }

    private static func registerAll() {
        let fontNames = [
            "SpaceGrotesk-Regular",
            "SpaceGrotesk-Medium",
            "SpaceGrotesk-Bold",
            "JetBrainsMono-SemiBold",
            "JetBrainsMono-Bold"
        ]

        for name in fontNames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
