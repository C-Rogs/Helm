import CoachLLM
import Core
import Foundation

/// Classifies all-day calendar event titles using the coach LLM.
/// Caches results so the same titles are not re-classified on every refresh.
@MainActor
final class CalendarEventClassifierService {
    private var cached: [String: EventBlockingClassification] = [:]

    /// Returns a classification for every day that has all-day events.
    /// Days without all-day events are not included in the result.
    func classify(
        loads: [HelmDay: CalendarDayLoad],
        provider: GeminiProvider? = CoachBootstrap.calendarGeminiProvider
    ) async -> [HelmDay: EventBlockingClassification] {
        var result: [HelmDay: EventBlockingClassification] = [:]

        let daysWithAllDayEvents = loads.filter { $0.value.hasAllDayEvent && !$0.value.allDayEventTitles.isEmpty }
        guard !daysWithAllDayEvents.isEmpty else { return result }

        var uncachedTitles: [String] = []
        for (_, load) in daysWithAllDayEvents {
            for title in load.allDayEventTitles {
                if cached[title] == nil, !uncachedTitles.contains(title) {
                    uncachedTitles.append(title)
                }
            }
        }

        if !uncachedTitles.isEmpty, let provider {
            do {
                let payload = try await provider.classifyCalendarEvents(titles: uncachedTitles)
                for entry in payload.classifications {
                    let classification: EventBlockingClassification = switch entry.classification {
                    case "fullyBlocking": .fullyBlocking
                    default: .partiallyBlocking
                    }
                    cached[entry.title] = classification
                }
                for title in uncachedTitles where cached[title] == nil {
                    cached[title] = .fullyBlocking
                }
            } catch {
                for title in uncachedTitles {
                    cached[title] = .fullyBlocking
                }
            }
        }

        for (helmDay, load) in daysWithAllDayEvents {
            result[helmDay] = CalendarEventClassifier.classify(
                titles: load.allDayEventTitles,
                known: cached
            )
        }

        return result
    }

    /// Returns fully-blocked days (sessions should avoid these).
    func fullyBlockedDays(
        classifications: [HelmDay: EventBlockingClassification]
    ) -> Set<HelmDay> {
        CalendarEventClassifier.fullyBlockedDays(from: [:], classifications: classifications)
    }

    /// Returns partially-blocked days (sessions stay in play but coach should negotiate).
    func partiallyBlockedDays(
        classifications: [HelmDay: EventBlockingClassification]
    ) -> Set<HelmDay> {
        CalendarEventClassifier.partiallyBlockedDays(from: classifications)
    }
}