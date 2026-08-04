import Core
import Foundation

struct CoachFoodMealConfirmState: Identifiable {
    let id = UUID()
    let estimate: MealEstimate
    let bucket: MealBucket
    let helmDay: HelmDay
    let coachReply: String
}
