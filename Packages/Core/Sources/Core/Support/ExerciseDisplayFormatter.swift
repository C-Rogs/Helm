import Foundation

public enum ExerciseDisplayFormatter {
    /// Prefer catalog display name; otherwise humanize the exercise ID (never show raw `seed-` prefix).
    public static func friendlyName(for exerciseID: String, displayNames: [String: String] = [:]) -> String {
        if let name = displayNames[exerciseID]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !name.isEmpty {
            return name
        }
        return humanizeID(exerciseID)
    }

    public static func humanizeID(_ exerciseID: String) -> String {
        var slug = exerciseID.trimmingCharacters(in: .whitespacesAndNewlines)
        if slug.hasPrefix("seed-") {
            slug = String(slug.dropFirst(5))
        }
        slug = slug.replacingOccurrences(of: "_", with: "-")
        return slug
            .split(separator: "-")
            .map { part in
                part.prefix(1).uppercased() + part.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}
