import Foundation

/// Lightweight bridge so CoachChatTextFormatter (CoachLLM package) can
/// surface citation-validation failures without a dependency on the app layer.
/// Wire the handler at app launch.
public enum CoachCitationDiagnostics: Sendable {
    nonisolated(unsafe) public static var handler: (@Sendable (String, String) -> Void)?

    public static func logFailure(_ type: CitationFailureType, rawTag: String) {
        handler?(type.rawValue, rawTag)
    }
}
