import Core
import Foundation

public enum BriefProgressionComposer {
    private static let weightKey = "helm.brief.progression.weight"
    private static let dietKey = "helm.brief.progression.diet"

    public static func deltaSentence(nutritionSnapshot: NutritionDaySnapshot) -> String? {
        var sentences: [String] = []

        if let weight = nutritionSnapshot.trend.smoothedTrendWeightKg {
            let rounded = (weight * 10).rounded() / 10
            let previous = UserDefaults.standard.object(forKey: weightKey) as? Double
            if let previous, abs(previous - rounded) >= 0.1 {
                if rounded < previous {
                    sentences.append("Trend weight is decreasing. Good work.")
                } else if rounded > previous {
                    sentences.append("Trend weight is rising. Keep an eye on intake.")
                }
            }
            UserDefaults.standard.set(rounded, forKey: weightKey)
        }

        if let average = nutritionSnapshot.trend.weeklyIntakeAverageKcal {
            let rounded = Int(average.rounded())
            let previous = UserDefaults.standard.integer(forKey: dietKey)
            if previous > 0, abs(previous - rounded) >= 50 {
                if rounded > previous {
                    sentences.append("Your 7-day diet average is climbing. Be careful if you are cutting.")
                } else if rounded < previous {
                    sentences.append("Your 7-day diet average is easing. Stay consistent with protein.")
                }
            }
            UserDefaults.standard.set(rounded, forKey: dietKey)
        }

        guard !sentences.isEmpty else { return nil }
        return sentences.joined(separator: " ")
    }
}
