import Foundation

enum CoachDisplayNameStore {
    private static let key = "helm.coach.displayName"

    static var name: String {
        get {
            let stored = UserDefaults.standard.string(forKey: key)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? "Coach" : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: key)
            } else {
                UserDefaults.standard.set(trimmed, forKey: key)
            }
        }
    }
}
