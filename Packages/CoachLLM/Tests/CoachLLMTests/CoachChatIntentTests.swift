import CoachLLM
import Core
import Foundation
import Testing

@Suite("CoachChatIntent")
struct CoachChatIntentTests {
    @Test("detects workout start vs proposal")
    func startVersusProposal() {
        #expect(CoachChatIntent.looksLikeWorkoutProposal("Make a full pull day workout"))
        #expect(!CoachChatIntent.looksLikeWorkoutStart("Make a full pull day workout"))
        #expect(CoachChatIntent.looksLikeWorkoutStart("Start the workout"))
        #expect(CoachChatIntent.looksLikeWorkoutStart("Yes let's go"))
        #expect(CoachChatIntent.looksLikeWorkoutStart("Yes go"))
        #expect(CoachChatIntent.shouldKeepWorkoutStart(
            "Yes go",
            lastAssistant: "Whenever you are ready to get started, let me know."
        ))
        #expect(CoachChatIntent.looksLikeWorkoutStart("Start a pull day with lat pulldown"))
        #expect(CoachChatIntent.looksLikeWorkoutStart("Make a workout with just bicep curls and start"))
        #expect(CoachChatIntent.looksLikeWorkoutStart("Start an example workout"))
        #expect(CoachChatIntent.shouldKeepWorkoutStart("Start the workout", lastAssistant: nil))
        #expect(CoachChatIntent.shouldKeepWorkoutStart("yes", lastAssistant: "Ready to lock this in and get started?"))
        #expect(CoachChatIntent.shouldKeepWorkoutStart("go", lastAssistant: "Ready to start this session?"))
        #expect(CoachChatIntent.shouldKeepWorkoutStart("yeah", lastAssistant: "Ready to start this session?"))
        #expect(!CoachChatIntent.shouldKeepWorkoutStart("go", lastAssistant: nil))
        #expect(!CoachChatIntent.shouldKeepWorkoutStart("go", lastAssistant: "How are your legs feeling?"))
        #expect(CoachChatIntent.confirmsPendingWorkoutStart("go"))
        #expect(CoachChatIntent.confirmsPendingWorkoutStart("Start workout"))
        #expect(CoachChatIntent.confirmsPendingWorkoutStart("Matt didn't you start"))
        #expect(!CoachChatIntent.confirmsPendingWorkoutStart("Why are you failing"))
        #expect(CoachChatIntent.looksLikeMissedWorkoutStart("Matt didn't you start"))
        #expect(CoachChatIntent.shouldForceWorkoutStartCard(
            "go",
            lastAssistant: "Ready to start this session?"
        ))
        #expect(CoachChatIntent.shouldForceWorkoutStartCard(
            "Start workout",
            lastAssistant: nil
        ))
        #expect(CoachChatIntent.shouldForceWorkoutStartCard(
            "Matt didn't you start",
            lastAssistant: "Ready to start this session?"
        ))
        #expect(!CoachChatIntent.shouldForceWorkoutStartCard(
            "go",
            lastAssistant: nil
        ))
        #expect(CoachChatIntent.isProseOnlyWorkoutStartConfirm("Confirm to start Shoulders & Arms Pump."))
        #expect(!CoachChatIntent.isProseOnlyWorkoutStartConfirm("Shoulders & Arms Pump"))
        let bubble = CoachChatIntent.workoutStartBubble(sessionTitle: "Shoulders & Arms Pump", modelText: "")
        #expect(bubble == "Shoulders & Arms Pump")
        #expect(!bubble.hasPrefix("Confirm to start"))
        let strippedBubble = CoachChatIntent.workoutStartBubble(
            sessionTitle: "Shoulders & Arms Pump",
            modelText: "Confirm to start Shoulders & Arms Pump."
        )
        #expect(strippedBubble == "Shoulders & Arms Pump")
        #expect(!CoachChatIntent.shouldKeepWorkoutStart("Why are you failing", lastAssistant: "Confirm to start Legs."))
        let repair = CoachChatIntent.athleteTurn(
            "Why are you failing",
            earlierUser: "Do you see how heavy I was this morning",
            earlierAssistant: "Confirm to start Legs."
        )
        #expect(repair.contains("[Reply failed]"))
        #expect(repair.contains("Do you see how heavy I was this morning"))
        #expect(!CoachChatIntent.athleteTurn("hello", earlierUser: nil, earlierAssistant: nil).contains("[Reply failed]"))
        #expect(!CoachChatIntent.shouldKeepWorkoutStart("Do you see how heavy I was this morning", lastAssistant: nil))
        #expect(!CoachChatIntent.shouldKeepWorkoutStart("yes", lastAssistant: "How are your legs feeling?"))
        #expect(!CoachChatIntent.looksLikeWorkoutStart("do not start a workout now let's just talk about it"))
        #expect(!CoachChatIntent.shouldKeepWorkoutStart(
            "do not start a workout now let's just talk about it",
            lastAssistant: nil
        ))
        #expect(CoachChatIntent.suppressesWriteProposals("do not start a workout now let's just talk about it"))
        #expect(CoachChatIntent.suppressesWriteProposals("All I said was hello"))
        #expect(CoachChatIntent.suppressesWriteProposals("Answer my questions"))
        #expect(CoachChatIntent.suppressesWriteProposals("Stop repeating the same thing"))
        #expect(CoachChatIntent.shouldDropUnsolicitedDeloadPitch("Hello"))
        #expect(CoachChatIntent.shouldDropUnsolicitedDeloadPitch("All I said was hello"))
        #expect(!CoachChatIntent.shouldDropUnsolicitedDeloadPitch("Why is my recovery low"))
        #expect(!CoachChatIntent.shouldRouteChatToSessionCoach(
            "Why did you swap the bench",
            sessionIsLive: true
        ))
        #expect(CoachChatIntent.shouldRouteChatToSessionCoach(
            "Remove a set of lateral raise",
            sessionIsLive: true
        ))
        #expect(CoachChatIntent.requiredWorkoutExerciseHint(from: "Start a pull day with lat pulldown") == "lat pulldown")
        #expect(
            CoachChatIntent.exerciseLabelsCoverHint(["Barbell Curl"], hint: "lat pulldown") == false
        )
        #expect(
            CoachChatIntent.exerciseLabelsCoverHint(["Wide Grip Lat Pulldown"], hint: "lat pulldown")
        )
        #expect(CoachChatIntent.clearsPendingWorkoutStart("How was my workout earlier"))
        #expect(!CoachChatIntent.clearsPendingWorkoutStart("Start the workout"))
        #expect(!CoachChatIntent.clearsPendingWorkoutStart("Hello coach"))
        #expect(CoachChatIntent.suppressesWriteProposals("Hello coach"))
        #expect(CoachChatIntent.suppressesWriteProposals("hi"))
        #expect(CoachChatIntent.suppressesWriteProposals("Hey!"))
        #expect(!CoachChatIntent.suppressesWriteProposals("I want to train on Friday"))
        #expect(!CoachChatIntent.suppressesWriteProposals("hello and swap Friday"))
    }

    @Test("infers workout and meal queries")
    func infersQueries() {
        #expect(CoachChatIntent.inferredWorkoutQuery(from: "How was my workout earlier")?.queryType == .latestCompleted)
        #expect(CoachChatIntent.inferredWorkoutQuery(from: "How was my workout including run")?.queryType == .includingCardio)
        #expect(CoachChatIntent.inferredMealQuery(from: "What did I have for breakfast on tuesday")?.queryType == .bucketOnDay)
        #expect(CoachChatIntent.inferredMealQuery(from: "previous meals from other days")?.queryType == .usualForBucket)
        let snack = CoachChatIntent.inferredMealQuery(from: "Can you see a snack I had yesterday")
        #expect(snack?.queryType == .bucketOnDay)
        #expect(snack?.bucket == "snacks")
        #expect(snack?.helmDay != nil)
        #expect(CoachChatIntent.looksLikeFoodLog("I ate an apple today"))
        #expect(!CoachChatIntent.looksLikePastMealLookup("I ate an apple today"))
        #expect(!CoachChatIntent.looksLikeFoodLog("Can you see a snack I had before"))
        #expect(CoachChatIntent.inferredRecoveryQuery(from: "HRV this week")?.queryType == .range)
        #expect(CoachChatIntent.inferredRecoveryQuery(from: "How did I sleep last night")?.queryType == .sleepDetail)
        #expect(CoachChatIntent.inferredRecoveryQuery(from: "How is my HRV today") == nil)
        #expect(CoachChatIntent.inferredRecoveryQuery(from: "Why is my recovery so low")?.queryType == .range)
        #expect(CoachChatIntent.inferredRecoveryQuery(from: "Did I sleep enough")?.queryType == .sleepDetail)
        #expect(CoachChatIntent.looksLikeScheduleReadQuestion("How many training days this week?"))
        #expect(!CoachChatIntent.looksLikeScheduleOverrideIntent(
            "Hello, I'm on my way to the gym. See what workouts I've done and what I need to do today."
        ))
        #expect(!CoachChatIntent.looksLikeScheduleOverrideIntent("How many training days this week?"))
        #expect(CoachChatIntent.looksLikeScheduleOverrideIntent("Pin legs today"))
        #expect(CoachChatIntent.looksLikeScheduleOverrideIntent("Swap Friday and Saturday"))
        #expect(CoachChatIntent.looksLikeScheduleOverrideIntent("My arms are sore, skip push"))
        #expect(CoachChatIntent.looksLikeScheduleOverrideIntent("Do legs today instead"))
        #expect(CoachChatIntent.looksLikeSchedulePinAnnouncement("Pinning Pull for today so your training aligns with your rotation."))
        #expect(
            CoachChatIntent.unsolicitedScheduleOverrideReply(prescribedSlot: "Legs")
                .contains("scheduled as Legs")
        )
        #expect(CoachChatIntent.suppressesWriteProposals("What days do I train?"))
        #expect(CoachChatIntent.suppressesWriteProposals("Let's talk about it first"))
        #expect(CoachChatIntent.suppressesWriteProposals("Cancel"))
        #expect(CoachChatIntent.dismissesPendingConfirm("Cancel"))
        #expect(CoachChatIntent.dismissesPendingConfirm("not yet"))
        #expect(!CoachChatIntent.dismissesPendingConfirm("Let's talk about bulking"))
        #expect(!CoachChatIntent.suppressesWriteProposals("Set my phase to gain"))
        #expect(CoachChatIntent.inferredHealthSync(from: "How up to date is that measurement") == nil)
        #expect(CoachChatIntent.inferredHealthSync(from: "Yes", lastAssistant: "Would you like me to refresh your HRV?") == nil)
        #expect(CoachChatIntent.inferredHealthSync(from: "Yes", lastAssistant: "How are the arms feeling?") == nil)
        #expect(CoachChatIntent.inferredHealthSync(from: "Yes", lastAssistant: "Want me to update the working weights?") == nil)
        #expect(CoachChatIntent.inferredHealthSync(from: "ok", lastAssistant: "I can pull the latest from your wearable.") == nil)
        #expect(CoachChatIntent.inferredHealthSync(from: "refresh my HRV") == nil)
        #expect(CoachChatIntent.inferredHealthSync(from: "refresh hrv") == nil)
        #expect(CoachChatIntent.inferredHealthSync(from: "Yes, pre-sync", lastAssistant: "We can do a quick sync. Would you like me to pull that latest data?") == nil)
        #expect(CoachChatIntent.structuredPromptLabels(from: "Would you like me to pull that latest data?")?.confirm == "Yes")
        #expect(CoachChatIntent.structuredPromptLabels(from: "How many sets do you want?")?.confirm == "Got it")
        #expect(CoachChatIntent.inferredHealthSync(from: "Re-sync with my calendar") == nil)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "Re-sync with my calendar") != nil)
        #expect(CoachChatIntent.inferredRecoveryQuery(from: "refresh my HRV") == nil)
        #expect(CoachChatIntent.inferredRecoveryQuery(from: "latest hrv") == nil)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "What events do I have today")?.queryType == .today)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "Why am I marked busy")?.queryType == .today)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "What's on my calendar this week")?.queryType == .weekAhead)
        let tomorrow = CoachChatIntent.inferredCalendarQuery(from: "What do I have on tomorrow")
        #expect(tomorrow?.queryType == .day)
        #expect(tomorrow?.helmDay != nil)
        let italy = CoachChatIntent.inferredCalendarQuery(
            from: "Yeah but Italy is in the calendar so you can see the dates"
        )
        #expect(italy?.queryType == .range)
        #expect(italy?.search == "Italy")
        #expect(italy?.lookaheadDays == 365)
        let unnamed = CoachChatIntent.inferredCalendarQuery(from: "You can see in my calendar right")
        #expect(unnamed?.queryType == .range)
        #expect(unnamed?.search == nil)
        #expect(unnamed?.lookaheadDays == 365)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "What's on my calendar")?.queryType == .today)
        let dateAsk = CoachChatIntent.inferredCalendarQuery(from: "What date do I go to Italy")
        #expect(dateAsk?.queryType == .range)
        #expect(dateAsk?.search == "Italy")
        #expect(dateAsk?.lookaheadDays == 365)
        let daysTill = CoachChatIntent.inferredCalendarQuery(from: "Im thinking about Italy how many days till I go")
        #expect(daysTill?.search == "Italy")
        #expect(CoachChatIntent.inferredCalendarQuery(from: "How long is the look ahead window") == nil)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "But you can search up future dates?") == nil)
        let thisWeekNamed = CoachChatIntent.inferredCalendarQuery(from: "Italy is in the calendar this week")
        #expect(thisWeekNamed?.search == "Italy")
        #expect(thisWeekNamed?.queryType == .range)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "When do I go to the gym") == nil)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "When am I going to train") == nil)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "How many days till I go to the gym") == nil)
        #expect(CoachChatIntent.inferredCalendarQuery(from: "When do I go to Italy")?.search == "Italy")
        #expect(CoachChatIntent.inferredTrendsQuery(from: "TRIMP history")?.queryType == .trimp)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "How has my weight trended")?.queryType == .weight)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "My e1rm progression")?.queryType == .e1rm)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "Energy balance history")?.queryType == .energyBalance)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "Readiness over time")?.queryType == .readiness)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "My trends")?.queryType == .all)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "search my body fat")?.queryType == .bodyFat)
        #expect(CoachChatIntent.inferredTrendsQuery(from: "What's my body fat percentage")?.queryType == .bodyFat)
        #expect(CoachChatIntent.inferredPatternQuery(from: "Have you noticed alcohol days")?.field == "alcohol")
        #expect(CoachChatIntent.inferredPatternQuery(from: "office days vs gym")?.field == "day_demand")
        #expect(CoachChatIntent.inferredPatternQuery(from: "when I drink does sleep change")?.field == "alcohol")
        #expect(CoachChatIntent.inferredPatternQuery(from: "My trends") == nil)
        let yesterday = CoachChatIntent.inferredWorkoutQuery(from: "Can you see the run I logged yesterday")
        #expect(yesterday?.queryType == .onDay)
        #expect(yesterday?.helmDay != nil)
        #expect(CoachChatIntent.looksLikeClearChat("clear chat"))
        #expect(!CoachChatIntent.looksLikeClearChat("clear my plate"))
    }

    // MARK: - Nutrition lookup

    @Test("looksLikeNutritionLookup detects nutrition-related phrases")
    func detectsNutritionLookup() {
        // Positive cases.
        #expect(CoachChatIntent.looksLikeNutritionLookup("What's my TDEE"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("what is my tdee"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("What should my macros be"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("macro target today"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("show me my weekly budget"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("calorie target"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("how many calories today"))
        #expect(CoachChatIntent.looksLikeNutritionLookup("what can i eat today"))
    }

    @Test("session adjustment intent is exercise-level, not plan or food")
    func sessionAdjustmentIntent() {
        #expect(CoachChatIntent.looksLikeSessionAdjustment("Swap bench for dumbbell press"))
        #expect(CoachChatIntent.looksLikeSessionAdjustment("Add a set to RDL"))
        #expect(CoachChatIntent.looksLikeSessionAdjustment("Take 5kg off the squat"))
        #expect(CoachChatIntent.looksLikeSessionAdjustment("Fill in the weights"))
        #expect(CoachChatIntent.looksLikeSessionAdjustment("Add weights to the new lifts"))
        #expect(CoachChatIntent.looksLikeWorkingLoadFill("Estimate working weights for these"))
        #expect(!CoachChatIntent.looksLikeWorkingLoadFill("How has my weight trended"))
        #expect(!CoachChatIntent.looksLikeSessionAdjustment("Start the workout"))
        #expect(!CoachChatIntent.looksLikeSessionAdjustment("How was my workout earlier"))
        #expect(!CoachChatIntent.looksLikeSessionAdjustment("What's my TDEE"))
        #expect(!CoachChatIntent.looksLikeSessionAdjustment("Swap my training plan to 4 days"))
        #expect(CoachChatIntent.shouldRouteChatToSessionCoach("Swap bench for incline", sessionIsLive: true))
        #expect(CoachChatIntent.shouldRouteChatToSessionCoach("Fill in the weights", sessionIsLive: true))
        #expect(!CoachChatIntent.shouldRouteChatToSessionCoach("Fill in the weights", sessionIsLive: false))
        #expect(!CoachChatIntent.shouldRouteChatToSessionCoach("Swap bench for incline", sessionIsLive: false))
        #expect(CoachChatIntent.shouldRouteChatToSessionCoach(
            "Swap bench for incline on today's session",
            sessionIsLive: false
        ))
    }

    @Test("chat food day ignores hidden nutrition diary unless the athlete named a date")
    func chatFoodDayIgnoresHiddenNutritionDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!
        let friday = calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 12))!
        let thursday = HelmDay(year: 2026, month: 8, day: 27)
        let unnamed = CoachChatIntent.resolvedChatFoodHelmDay(
            userText: "log 400 calories of chicken",
            payloadDay: thursday.formatted,
            nutritionTabVisible: false,
            viewedNutritionDay: thursday.formatted,
            now: friday,
            calendar: calendar
        )
        #expect(unnamed == HelmDay.day(for: friday, calendar: calendar))

        let named = CoachChatIntent.resolvedChatFoodHelmDay(
            userText: "log 400 calories of chicken yesterday",
            payloadDay: nil,
            nutritionTabVisible: false,
            now: friday,
            calendar: calendar
        )
        #expect(named == thursday)

        let onNutrition = CoachChatIntent.resolvedChatFoodHelmDay(
            userText: "log 400 calories of chicken",
            payloadDay: thursday.formatted,
            nutritionTabVisible: true,
            now: friday,
            calendar: calendar
        )
        #expect(onNutrition == thursday)
    }

    @Test("open train and open snack entry infer navigate tabs")
    func infersNavigateTab() {
        #expect(CoachChatIntent.inferredNavigateTab(from: "Open train") == "train")
        #expect(CoachChatIntent.inferredNavigateTab(from: "Open settings") == "settings")
        #expect(CoachChatIntent.inferredNavigateTab(from: "open the entry of the snack I just logged") == "nutrition")
        #expect(CoachChatIntent.inferredNavigateTab(from: "I am open to swapping bench") == nil)
    }

    @Test("looksLikeNutritionLookup does not match unrelated phrases")
    func doesNotDetectNonNutritionPhrases() {
        // Negative cases.
        #expect(!CoachChatIntent.looksLikeNutritionLookup("log 300g of chicken"))
        #expect(!CoachChatIntent.looksLikeNutritionLookup("What should I do for my workout today"))
        #expect(!CoachChatIntent.looksLikeNutritionLookup("How was my sleep last night"))
        #expect(!CoachChatIntent.looksLikeNutritionLookup("add breakfast"))
        #expect(!CoachChatIntent.looksLikeNutritionLookup("yesterday I had 2000 calories"))
    }

    @Test("inferredNutritionQuery returns weeklyBudget for budget keywords and today otherwise")
    func infersNutritionQuery() {
        let budget = CoachChatIntent.inferredNutritionQuery(from: "Show me my weekly budget")
        #expect(budget?.queryType == .weeklyBudget)

        let week = CoachChatIntent.inferredNutritionQuery(from: "What's my nutrition budget")
        #expect(week?.queryType == .weeklyBudget)

        let weekAhead = CoachChatIntent.inferredNutritionQuery(from: "Plan my week ahead nutrition")
        #expect(weekAhead?.queryType == .weeklyBudget)

        let today = CoachChatIntent.inferredNutritionQuery(from: "What's my TDEE")
        #expect(today?.queryType == .today)

        let macros = CoachChatIntent.inferredNutritionQuery(from: "What should my macros be")
        #expect(macros?.queryType == .today)

        let history = CoachChatIntent.inferredNutritionQuery(from: "calorie history")
        #expect(history?.queryType == .range)

        let weeklyHistory = CoachChatIntent.inferredNutritionQuery(from: "weekly calorie history")
        #expect(weeklyHistory?.queryType == .range)

        let pastIntake = CoachChatIntent.inferredNutritionQuery(from: "past intake")
        #expect(pastIntake?.queryType == .range)

        let nilQuery = CoachChatIntent.inferredNutritionQuery(from: "log breakfast")
        #expect(nilQuery == nil)
    }

    @Test("chart and navigation intents from 28 Aug dump")
    func chartAndNavigationIntents() {
        #expect(CoachChatIntent.looksLikeChartRequest("Show me the sweetest Hard stes as a chart"))
        #expect(CoachChatIntent.inferredChartKind(from: "Show me the sweetest Hard stes as a chart") == .hardSets)
        #expect(CoachChatIntent.inferredChartKind(from: "Show this week calories as a chart") == .weeklyCalories)
        #expect(CoachChatIntent.looksLikeOpenTrain("Open train"))
        #expect(CoachChatIntent.looksLikeOpenNutrition("Open the entry of the snack I just locked"))
        #expect(CoachChatIntent.looksLikeOpenNutrition("Navigate to chicken nutrition log yesterday"))
        #expect(!CoachChatIntent.looksLikeOpenNutrition("Show this week calories as a chart"))
    }

    @Test("food log helm day follows athlete date cues")
    func foodLogHelmDayCues() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 8, day: 28, hour: 16))!
        #expect(
            CoachChatIntent.inferredHelmDay(
                from: "Cheese on toast (log to lunch) for 2026-08-27",
                now: now,
                calendar: calendar
            ) == HelmDay(year: 2026, month: 8, day: 27)
        )
        #expect(
            CoachChatIntent.inferredHelmDay(
                from: "Block 400 cow chickens for lunch",
                now: now,
                calendar: calendar
            ) == nil
        )
        #expect(
            CoachChatIntent.inferredHelmDay(
                from: "I just had a naked fruit and nut bar log it",
                now: now,
                calendar: calendar
            ) == nil
        )
        #expect(
            CoachChatIntent.inferredHelmDay(
                from: "log yesterday lunch",
                now: now,
                calendar: calendar
            ) == HelmDay(year: 2026, month: 8, day: 27)
        )
    }

    @Test("weekday-only Sunday dinner forces meal_query without matching query or nutrition_day")
    func weekdayOnlySundayForcesMealQuery() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        // Early Tuesday morning: still Monday HelmDay under 04:00 cutoff (CAM-44/45).
        let afterMidnight = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 1))!
        let afternoon = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 14))!
        let sunday = HelmDay(year: 2026, month: 9, day: 6)
        #expect(HelmDay.day(for: afterMidnight, calendar: calendar) == HelmDay(year: 2026, month: 9, day: 7))
        #expect(
            CoachChatIntent.weekdayOnlyMealDay(
                from: "Delete all the dinner items on Sunday",
                now: afterMidnight,
                calendar: calendar
            ) == sunday
        )
        #expect(
            CoachChatIntent.weekdayOnlyMealDay(
                from: "Delete Sundays dinner",
                now: afterMidnight,
                calendar: calendar
            ) == sunday
        )
        #expect(
            CoachChatIntent.shouldForceMealQueryForWeekdayMealOp(
                userText: "Delete Sundays dinner",
                mealQueryDay: nil,
                mealQueryIsFresh: false,
                nutritionTabVisible: false,
                viewedNutritionDay: nil,
                now: afternoon,
                calendar: calendar
            )
        )
        #expect(
            !CoachChatIntent.shouldForceMealQueryForWeekdayMealOp(
                userText: "Delete Sundays dinner",
                mealQueryDay: sunday,
                mealQueryIsFresh: true,
                nutritionTabVisible: false,
                viewedNutritionDay: nil,
                now: afternoon,
                calendar: calendar
            )
        )
        #expect(
            CoachChatIntent.weekdayConflictsWithPayloadDay(
                userText: "Delete Sundays dinner",
                payloadDay: "2026-09-07",
                now: afternoon,
                calendar: calendar
            )
        )
        #expect(
            !CoachChatIntent.weekdayConflictsWithPayloadDay(
                userText: "Delete Sundays dinner",
                payloadDay: "2026-09-06",
                now: afternoon,
                calendar: calendar
            )
        )
        #expect(
            CoachChatIntent.weekdayOnlyMealDay(
                from: "delete yesterday dinner",
                now: afternoon,
                calendar: calendar
            ) == nil
        )
    }
}

@Suite("CoachThreadState")
struct CoachThreadStateTests {
    @Test("windows to most recent messages")
    func windowsMessages() {
        let messages = (0 ..< 25).map { CoachMessage(role: .user, text: "m\($0)") }
        let windowed = CoachThreadState(messages: messages).windowed(limit: 20)
        #expect(windowed.messages.count == 20)
        #expect(windowed.messages.first?.text == "m5")
        #expect(windowed.messages.last?.text == "m24")
    }
}

@Suite("CoachTranscriptBuilder")
struct CoachTranscriptBuilderTests {
    @Test("does not duplicate trailing user message")
    func dropsTrailingDuplicate() {
        let thread = CoachThreadState(messages: [
            CoachMessage(role: .user, text: "hello"),
            CoachMessage(role: .assistant, text: "hi"),
            CoachMessage(role: .user, text: "start it")
        ])
        let contents = CoachTranscriptBuilder.contents(
            systemInstructions: "sys",
            contextBlock: "",
            userMessage: "start it",
            thread: thread
        )
        let userTexts = contents.compactMap { row -> String? in
            guard row["role"] as? String == "user",
                  let parts = row["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String
            else { return nil }
            return text
        }
        #expect(userTexts.filter { $0 == "start it" }.count == 1)
        #expect(userTexts.contains("hello"))
    }

    @Test("reference pack is not a turn the coach agrees to")
    func referencePackStaysOutOfTheConversation() throws {
        let body = try GeminiRequestBuilder.streamChatBody(
            systemInstructions: "You are a PT.",
            contextBlock: "readiness=29",
            userMessage: "hello",
            thread: .empty
        ).encoded()
        let object = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
        let system = try #require(object["system_instruction"] as? [String: Any])
        let systemText = ((system["parts"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        #expect(systemText.contains("Reference pack"))
        #expect(systemText.contains("readiness=29"))
        let contents = try #require(object["contents"] as? [[String: Any]])
        let blob = String(describing: contents)
        #expect(!blob.contains("Understood."))
        #expect(!blob.contains("readiness=29"))
        #expect(blob.contains("hello"))
    }
}

@Suite("WorkoutStartStructuredPayload")
struct WorkoutStartStructuredPayloadTests {
    @Test("embeds start json for parser")
    func embedsJSON() throws {
        let payload = WorkoutStartStructuredPayload(
            reply: "Starting pull.",
            helmDay: "2026-08-03",
            title: "Pull",
            exercises: [
                .init(
                    name: "Lat Pulldown",
                    restSeconds: 90,
                    sets: [.init(setType: "normal", reps: 8, massKg: 52.5, rpe: 8)]
                )
            ]
        )
        let text = try payload.chatAssemblyText()
        #expect(text.hasPrefix("Starting pull."))
        #expect(text.contains("\"schemaVersion\":\"workout_start.v2\""))
        #expect(text.contains("Lat Pulldown"))
    }

    @Test("embeds native cardio interval values")
    func embedsCardioJSON() throws {
        let payload = WorkoutStartStructuredPayload(
            reply: "Starting a ten minute jog.",
            title: "Easy jog",
            exercises: [
                .init(
                    name: "Treadmill",
                    sets: [
                        .init(durationSeconds: 600, distanceKilometers: 2, rpe: 6)
                    ]
                )
            ]
        )
        let text = try payload.chatAssemblyText()
        #expect(text.contains("\"durationSeconds\":600"))
        #expect(text.contains("\"distanceKilometers\":2"))
        #expect(!text.contains("\"massKg\""))
        #expect(!text.contains("\"reps\""))
    }
}
