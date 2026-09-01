import Core
import Foundation
import Persistence
import Testing
@testable import HealthKitIngest

@Suite("Usual meal resolver")
struct UsualMealResolverTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private let tuesday = HelmDay(year: 2026, month: 9, day: 1)
    private let monday = HelmDay(year: 2026, month: 8, day: 31)
    private let friday = HelmDay(year: 2026, month: 8, day: 28)
    private let saturday = HelmDay(year: 2026, month: 8, day: 29)
    private let sunday = HelmDay(year: 2026, month: 8, day: 30)
    private let nextSaturday = HelmDay(year: 2026, month: 9, day: 5)

    @Test("weekday prefers named template used on weekdays")
    func weekdayPrefersWorkBreakfastTemplate() throws {
        let store = try PersistenceStore.inMemory()
        let template = workBreakfastTemplate(updatedAt: date(year: 2026, month: 8, day: 31, hour: 8))
        try store.mealTemplates.save(template)
        try insertMeal(
            store: store,
            day: monday,
            bucket: .breakfast,
            name: "Work breakfast",
            kcal: 520,
            hour: 8
        )

        let resolver = UsualMealResolver(store: store, calendar: calendar)
        let proposal = try resolver.proposal(for: .breakfast, on: tuesday)
        #expect(proposal?.displayName == "Work breakfast")
        #expect(proposal?.energyKcal == 520)
        guard case .template(let resolved)? = proposal?.source else {
            Issue.record("expected template")
            return
        }
        #expect(resolved.id == template.id)
    }

    @Test("weekend stays quiet when only weekday template history exists")
    func weekendStaysQuietWithoutWeekendPattern() throws {
        let store = try PersistenceStore.inMemory()
        try store.mealTemplates.save(workBreakfastTemplate(updatedAt: date(year: 2026, month: 8, day: 31, hour: 8)))
        try insertMeal(
            store: store,
            day: monday,
            bucket: .breakfast,
            name: "Work breakfast",
            kcal: 520,
            hour: 8
        )

        let resolver = UsualMealResolver(store: store, calendar: calendar)
        let proposal = try resolver.proposal(for: .breakfast, on: nextSaturday)
        #expect(proposal == nil)
    }

    @Test("copies last matching weekday when no template matches")
    func copiesLastMatchingWeekday() throws {
        let store = try PersistenceStore.inMemory()
        try insertMeal(store: store, day: friday, bucket: .breakfast, name: "Oats", kcal: 400, hour: 8)
        try insertMeal(store: store, day: monday, bucket: .breakfast, name: "Oats", kcal: 410, hour: 8)

        let resolver = UsualMealResolver(store: store, calendar: calendar)
        let proposal = try resolver.proposal(for: .breakfast, on: tuesday)
        #expect(proposal?.displayName == "Oats")
        #expect(proposal?.energyKcal == 410)
        #expect(proposal?.source == .copy(from: monday))
    }

    @Test("uses weekend copy on Saturday")
    func weekendCopyFromLastWeekend() throws {
        let store = try PersistenceStore.inMemory()
        try insertMeal(store: store, day: saturday, bucket: .breakfast, name: "Brunch", kcal: 700, hour: 10)
        try insertMeal(store: store, day: sunday, bucket: .breakfast, name: "Brunch", kcal: 680, hour: 10)

        let resolver = UsualMealResolver(store: store, calendar: calendar)
        let proposal = try resolver.proposal(for: .breakfast, on: nextSaturday)
        #expect(proposal?.displayName == "Brunch")
        #expect(proposal?.source == .copy(from: sunday))
    }

    @Test("returns nil when the bucket is already logged")
    func alreadyLoggedReturnsNil() throws {
        let store = try PersistenceStore.inMemory()
        try store.mealTemplates.save(workBreakfastTemplate(updatedAt: date(year: 2026, month: 8, day: 31, hour: 8)))
        try insertMeal(store: store, day: monday, bucket: .breakfast, name: "Work breakfast", kcal: 520, hour: 8)
        try insertMeal(store: store, day: tuesday, bucket: .breakfast, name: "Something else", kcal: 300, hour: 9)

        let resolver = UsualMealResolver(store: store, calendar: calendar)
        #expect(try resolver.proposal(for: .breakfast, on: tuesday) == nil)
    }

    @Test("weekday with a single unused template still proposes it")
    func weekdayOnboardingTemplate() throws {
        let store = try PersistenceStore.inMemory()
        try store.mealTemplates.save(workBreakfastTemplate(updatedAt: date(year: 2026, month: 8, day: 31, hour: 8)))

        let resolver = UsualMealResolver(store: store, calendar: calendar)
        let proposal = try resolver.proposal(for: .breakfast, on: tuesday)
        #expect(proposal?.displayName == "Work breakfast")
        guard case .template? = proposal?.source else {
            Issue.record("expected template")
            return
        }
    }

    @Test("snacks need two matching samples")
    func snacksRequireStablePattern() throws {
        let store = try PersistenceStore.inMemory()
        try insertMeal(store: store, day: monday, bucket: .snacks, name: "Yogurt", kcal: 150, hour: 16)

        let resolver = UsualMealResolver(store: store, calendar: calendar)
        #expect(try resolver.proposal(for: .snacks, on: tuesday) == nil)

        try insertMeal(store: store, day: friday, bucket: .snacks, name: "Yogurt", kcal: 150, hour: 16)
        let proposal = try resolver.proposal(for: .snacks, on: tuesday)
        #expect(proposal?.displayName == "Yogurt")
        #expect(proposal?.source == .copy(from: monday))
    }

    @Test("logUsual writes the template onto an empty bucket")
    func logUsualWritesTemplate() async throws {
        let store = try PersistenceStore.inMemory()
        let meals = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store, calendar: calendar)
        )
        let template = workBreakfastTemplate(updatedAt: date(year: 2026, month: 8, day: 31, hour: 8))
        try store.mealTemplates.save(template)
        try insertMeal(store: store, day: monday, bucket: .breakfast, name: "Work breakfast", kcal: 520, hour: 8)

        let executor = HelmActionExecutor(
            manualMealService: meals,
            persistence: store,
            mealRepeatService: MealRepeatService(store: store, manualMealService: meals),
            calendar: calendar
        )
        let loggedAt = date(year: 2026, month: 9, day: 1, hour: 9)
        let result = try await executor.run(
            .logUsual(bucket: .breakfast, helmDay: tuesday, loggedAt: loggedAt, proposal: nil)
        )
        #expect(result.nutritionDay == tuesday)
        let todayMeals = try store.nutrition.fetchMeals(for: tuesday)
        #expect(todayMeals.count == 1)
        #expect(todayMeals[0].name == "Work breakfast")
        #expect(todayMeals[0].source == .template)
    }

    @Test("logUsual uses a passed proposal without resolving history")
    func logUsualUsesPassedProposal() async throws {
        let store = try PersistenceStore.inMemory()
        let meals = ManualMealService(
            writer: MealHealthKitWriter(store: MockHealthKitStoreClient()),
            localStore: ManualMealLocalStore(store: store, calendar: calendar)
        )
        let template = workBreakfastTemplate(updatedAt: date(year: 2026, month: 8, day: 31, hour: 8))
        let proposal = UsualMealProposal(
            bucket: .breakfast,
            displayName: template.name,
            energyKcal: 520,
            source: .template(template)
        )
        let executor = HelmActionExecutor(
            manualMealService: meals,
            persistence: store,
            mealRepeatService: MealRepeatService(store: store, manualMealService: meals),
            calendar: calendar
        )
        let loggedAt = date(year: 2026, month: 9, day: 1, hour: 9)
        _ = try await executor.run(
            .logUsual(bucket: .breakfast, helmDay: tuesday, loggedAt: loggedAt, proposal: proposal)
        )
        let todayMeals = try store.nutrition.fetchMeals(for: tuesday)
        #expect(todayMeals.count == 1)
        #expect(todayMeals[0].name == "Work breakfast")
        #expect(todayMeals[0].source == .template)
    }

    @Test("logUsual throws when the bucket is already filled")
    func logUsualThrowsWhenFilled() async throws {
        let store = try PersistenceStore.inMemory()
        try insertMeal(store: store, day: tuesday, bucket: .breakfast, name: "Oats", kcal: 400, hour: 8)
        let executor = HelmActionExecutor(persistence: store, calendar: calendar)
        await #expect(throws: UsualMealLogError.alreadyLogged) {
            try await executor.run(
                .logUsual(
                    bucket: .breakfast,
                    helmDay: tuesday,
                    loggedAt: date(year: 2026, month: 9, day: 1, hour: 9),
                    proposal: nil
                )
            )
        }
    }

    private func workBreakfastTemplate(updatedAt: Date) -> MealTemplate {
        MealTemplate(
            name: "Work breakfast",
            bucket: .breakfast,
            lineItems: [
                MealLineItem(
                    name: "Oats",
                    grams: 60,
                    caloriesKcal: 230,
                    proteinG: 8,
                    carbsG: 40,
                    fatG: 4,
                    matchConfidence: .high
                ),
                MealLineItem(
                    name: "Yogurt",
                    grams: 200,
                    caloriesKcal: 290,
                    proteinG: 20,
                    carbsG: 30,
                    fatG: 8,
                    matchConfidence: .high
                )
            ],
            updatedAt: updatedAt
        )
    }

    private func insertMeal(
        store: PersistenceStore,
        day: HelmDay,
        bucket: MealBucket,
        name: String,
        kcal: Double,
        hour: Int
    ) throws {
        let loggedAt = date(year: day.year, month: day.month, day: day.day, hour: hour)
        try store.nutrition.upsertMeal(
            MealRecord(
                helmDay: day,
                name: name,
                loggedAt: loggedAt,
                bucket: bucket,
                energy: Energy(kilocalories: kcal),
                proteinGrams: 20,
                carbohydrateGrams: 40,
                fatGrams: 10,
                source: .template
            )
        )
    }

    private func date(year: Int, month: Int, day: Int, hour: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: 0))!
    }
}

@Suite("Usual meal fire planner")
struct UsualMealFirePlannerTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private let tuesday = HelmDay(year: 2026, month: 9, day: 1)

    @Test("default breakfast fires at 09:00 when still before the window")
    func defaultBreakfastFireTime() {
        let now = date(hour: 7, minute: 0)
        let fire = UsualMealFirePlanner.fireDate(
            day: tuesday,
            bucket: .breakfast,
            sampleLoggedAts: [],
            now: now,
            calendar: calendar
        )
        let expected = date(hour: 9, minute: 0)
        #expect(fire == expected)
    }

    @Test("learned log time plus 15 minutes")
    func learnedTimePlusBuffer() {
        let now = date(hour: 7, minute: 0)
        let samples = [date(hour: 8, minute: 10), date(hour: 8, minute: 20)]
        let fire = UsualMealFirePlanner.fireDate(
            day: tuesday,
            bucket: .breakfast,
            sampleLoggedAts: samples,
            now: now,
            calendar: calendar
        )
        #expect(fire == date(hour: 8, minute: 30))
    }

    @Test("overdue inside the window fires soon")
    func overdueInsideWindowFiresSoon() {
        let now = date(hour: 10, minute: 0)
        let fire = UsualMealFirePlanner.fireDate(
            day: tuesday,
            bucket: .breakfast,
            sampleLoggedAts: [],
            now: now,
            calendar: calendar
        )
        #expect(fire == now.addingTimeInterval(UsualMealFirePlanner.overdueLeadSeconds))
    }

    @Test("past breakfast window does not fire")
    func pastWindowDoesNotFire() {
        let now = date(hour: 13, minute: 0)
        let fire = UsualMealFirePlanner.fireDate(
            day: tuesday,
            bucket: .breakfast,
            sampleLoggedAts: [],
            now: now,
            calendar: calendar
        )
        #expect(fire == nil)
    }

    private func date(hour: Int, minute: Int) -> Date {
        calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 1, hour: hour, minute: minute)
        )!
    }
}

@Suite("Usual meal notification planner")
struct UsualMealNotificationPlannerTests {
    @Test("identifier encodes day and bucket")
    func identifierEncodesDayAndBucket() {
        let day = HelmDay(year: 2026, month: 9, day: 1)
        let identifier = UsualMealNotificationPlanner.notificationIdentifier(day: day, bucket: .breakfast)
        #expect(identifier == "helm.usual_meal.2026-09-01.breakfast")
        #expect(UsualMealNotificationPlanner.isUsualMeal(categoryIdentifier: "helm.usual_meal"))
        let info = UsualMealNotificationPlanner.userInfo(day: day, bucket: .lunch)
        #expect(UsualMealNotificationPlanner.bucket(fromUserInfo: info) == .lunch)
        #expect(UsualMealNotificationPlanner.helmDay(fromUserInfo: info) == day)
    }

    @Test("copy names the usual without forgot")
    func copyAvoidsForgot() {
        let proposal = UsualMealProposal(
            bucket: .breakfast,
            displayName: "Work breakfast",
            energyKcal: 520,
            source: .copy(from: HelmDay(year: 2026, month: 8, day: 31))
        )
        #expect(UsualMealNotificationPlanner.title(proposal: proposal) == "Usual Work breakfast?")
        #expect(UsualMealNotificationPlanner.body(proposal: proposal) == "520 kcal. Yes logs it.")
    }
}
