import CoachLLM
import Core
import Foundation

/// Classifies all-day calendar event titles using the coach LLM.
/// Cache persists across launches (UserDefaults) and invalidates on prompt version bump.
/// Concurrent calls share a single in-flight request (single-flight coalesce).
@MainActor
final class CalendarEventClassifierService {
    private var cached: [String: EventBlockingClassification] = [:]
    private var inFlightTask: Task<[String: EventBlockingClassification], Error>?
    private let defaults: UserDefaults

    private enum Key {
        static let cache = "calendar_event_classify_cache"
        static let promptVersion = "calendar_event_classify_prompt_version"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadPersistedCache()
    }

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
                let classifications = try await classifyInFlight(titles: uncachedTitles, provider: provider)
                for (title, classification) in classifications {
                    cached[title] = classification
                }
                for title in uncachedTitles where cached[title] == nil {
                    cached[title] = .fullyBlocking
                }
                persistCache()
            } catch {
                for title in uncachedTitles {
                    cached[title] = .fullyBlocking
                }
                persistCache()
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

    // MARK: - Single-flight coalesce

    private func classifyInFlight(
        titles: [String],
        provider: GeminiProvider
    ) async throws -> [String: EventBlockingClassification] {
        if let existing = inFlightTask {
            let classifications = try await existing.value
            inFlightTask = nil
            return classifications
        }

        let task = Task<[String: EventBlockingClassification], Error> {
            let payload = try await provider.classifyCalendarEvents(titles: titles)
            var result: [String: EventBlockingClassification] = [:]
            for entry in payload.classifications {
                result[entry.title] = switch entry.classification {
                case "fullyBlocking": .fullyBlocking
                default: .partiallyBlocking
                }
            }
            return result
        }
        inFlightTask = task
        defer { inFlightTask = nil }

        return try await task.value
    }

    // MARK: - Persistence

    private func loadPersistedCache() {
        let storedVersion = defaults.string(forKey: Key.promptVersion)
        let currentVersion = CoachPromptVersion.calendarEventClassifyV1.rawValue
        guard storedVersion == currentVersion else {
            defaults.removeObject(forKey: Key.cache)
            defaults.removeObject(forKey: Key.promptVersion)
            return
        }

        guard let data = defaults.data(forKey: Key.cache),
              let decoded = try? JSONDecoder().decode([String: EventBlockingClassification].self, from: data)
        else {
            return
        }
        cached = decoded
    }

    private func persistCache() {
        guard let data = try? JSONEncoder().encode(cached) else { return }
        defaults.set(data, forKey: Key.cache)
        defaults.set(CoachPromptVersion.calendarEventClassifyV1.rawValue, forKey: Key.promptVersion)
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