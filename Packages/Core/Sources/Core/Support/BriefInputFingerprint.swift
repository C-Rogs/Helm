import Foundation

public enum BriefInputFingerprint {
    /// Bump when engine brief copy shape changes so cached briefs regenerate.
    private static let copyRevision = "v3-patterns"

    public static func compute(from snapshot: BriefInputsSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return "invalid"
        }
        return "\(copyRevision)|\(json)"
    }
}
