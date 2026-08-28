import Foundation

/// Live app chrome Coach should know: selected tab and whether a session is running.
/// Rides on the transcript freshness suffix so the cached context block stays stable.
public struct CoachAppSurfaceSnapshot: Sendable, Equatable {
    public let selectedTab: String
    public let sessionStatus: String
    public let sessionTitle: String?

    public init(
        selectedTab: String,
        sessionStatus: String,
        sessionTitle: String? = nil
    ) {
        self.selectedTab = selectedTab
        self.sessionStatus = sessionStatus
        self.sessionTitle = sessionTitle
    }

    public var contextText: String {
        var lines = [
            "# App State",
            "tab=\(selectedTab)",
            "session=\(sessionStatus)"
        ]
        if let sessionTitle, !sessionTitle.isEmpty {
            lines.append("session_title=\(sessionTitle)")
        }
        return lines.joined(separator: "\n")
    }
}
