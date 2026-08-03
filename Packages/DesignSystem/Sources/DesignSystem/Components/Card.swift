import SwiftUI

public struct Card<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        SkinnedContainer {
            content
        }
    }
}

#Preview("Card signal") {
    Card {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Readiness")
                .helmType(.label)
            Text("Building baseline")
                .helmType(.body, color: HelmColor.fgSecondary)
        }
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .signal)
}

#Preview("Card instrument") {
    Card {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Readiness")
                .helmType(.label)
            Text("Building baseline")
                .helmType(.body, color: HelmColor.fgSecondary)
        }
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .instrument)
}

#Preview("Card data sheet") {
    Card {
        VStack(alignment: .leading, spacing: HelmSpacing.xs) {
            Text("Readiness")
                .helmType(.label)
            Text("Building baseline")
                .helmType(.body, color: HelmColor.fgSecondary)
        }
    }
    .padding()
    .helmTheme()
    .environment(\.helmSkin, .dataSheet)
}
