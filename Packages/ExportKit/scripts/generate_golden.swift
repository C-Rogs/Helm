import ExportKit
import Foundation

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/London")!

let day6 = calendar.date(from: DateComponents(year: 2026, month: 7, day: 6))!
let day7 = calendar.date(from: DateComponents(year: 2026, month: 7, day: 7))!
let dayKey6 = BioharvestHealthKitMath.startOfCalendarDay(day6, calendar: calendar)
let dayKey7 = BioharvestHealthKitMath.startOfCalendarDay(day7, calendar: calendar)

let metrics = SchemaV2MetricBundle(
    hrv: [dayKey6: 38.1, dayKey7: 42.3],
    rhr: [dayKey6: nil, dayKey7: 58.5],
    sleep: SchemaV2SleepSeries(
        total: [dayKey6: 390, dayKey7: 420],
        deep: [dayKey6: nil, dayKey7: 90],
        rem: [dayKey6: 95, dayKey7: 105]
    ),
    steps: [dayKey6: 6200, dayKey7: 8500],
    weight: [dayKey7: 78.2],
    bodyFat: [dayKey7: 14.5],
    activeEnergy: [dayKey7: 450],
    restingEnergy: [dayKey7: 1650],
    exerciseMinutes: [dayKey7: 45],
    calories: [dayKey7: 2100],
    protein: [dayKey7: 140],
    carbs: [dayKey7: 220],
    fat: [dayKey7: 65],
    water: [dayKey7: 2.5],
    alcohol: [dayKey6: 0, dayKey7: 0],
    workouts: [
        dayKey7: [
            WorkoutLog(
                type: "Running",
                durationMinutes: RoundedDouble(35),
                energyBurnedKcal: RoundedDouble(320),
                effortScore: RoundedDouble(6.5),
                trainingLoadContribution: RoundedDouble(8.2)
            )
        ]
    ],
    trainingLoad: [dayKey7: 12.5]
)

let logs = SchemaV2DailyLogAssembler.assemble(
    days: [day6, day7],
    inclusion: MetricInclusion(),
    metrics: metrics,
    calendar: calendar,
    timezoneIdentifier: "Europe/London"
)

let exportDate = ISO8601DateFormatter().date(from: "2026-07-08T10:00:00Z")!
let payload = SchemaV2ExportPipeline.buildPayload(
    window: SchemaV2ExportWindow(start: day6, end: day7),
    inclusion: MetricInclusion(),
    logs: logs,
    healthKitStatus: .liveAuthorized,
    exportDate: exportDate,
    calendar: calendar
)

let data = try! SchemaV2Encoder.encode(payload, style: .humanReadable)
let path = "Tests/ExportKitTests/Fixtures/bioharvest_golden.json"
try! data.write(to: URL(fileURLWithPath: path))
print("wrote \(data.count) bytes to \(path)")
