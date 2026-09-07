import SwiftUI

/// Parses lightweight markdown (`**bold**`, `*italic*`, links) for coach copy.
public enum HelmMarkdown {
    public static func attributed(_ string: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: string, options: options))
            ?? AttributedString(string)
    }
}

/// Body text that renders inline markdown while keeping Helm type styles as the base.
public struct HelmMarkdownText: View {
    private let text: String
    private let style: HelmType
    private let color: Color?

    public init(
        _ text: String,
        style: HelmType = .body,
        color: Color? = nil
    ) {
        self.text = text
        self.style = style
        self.color = color
    }

    public var body: some View {
        Group {
            if let color {
                Text(HelmMarkdown.attributed(text))
                    .helmType(style, color: color)
            } else {
                Text(HelmMarkdown.attributed(text))
                    .helmType(style)
            }
        }
    }
}
