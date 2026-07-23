import Foundation

public enum BriefInputFingerprint {
    public static func compute(from snapshot: BriefInputsSnapshot) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(snapshot),
              let json = String(data: data, encoding: .utf8) else {
            return "invalid"
        }
        return json
    }
}
