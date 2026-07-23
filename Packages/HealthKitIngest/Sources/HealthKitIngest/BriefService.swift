import CoachLLM
import Core
import Diagnostics
import Foundation
import OSLog
import Persistence
import ReadinessKit

public enum BriefDashboardState: Sendable, Equatable {
    case loading
    case ready(BriefCardModel)
}

public struct BriefCardModel: Sendable, Equatable {
    public let narration: String
    public let citationLabel: String?
    public let isEngineOnly: Bool

    public init(narration: String, citationLabel: String?, isEngineOnly: Bool) {
        self.narration = narration
        self.citationLabel = citationLabel
        self.isEngineOnly = isEngineOnly
    }
}

public actor BriefEngine {
    private let persistence: PersistenceStore
    private let prescriptionEngine: PlanPrescriptionEngine
    private let narrator: MorningBriefNarrator
    private let log: Logger

    public init(
        persistence: PersistenceStore,
        prescriptionEngine: PlanPrescriptionEngine,
        narrator: MorningBriefNarrator = .live()
    ) {
        self.persistence = persistence
        self.prescriptionEngine = prescriptionEngine
        self.narrator = narrator
        log = helmLogger(category: .healthKitIngest)
    }

    public func ensureBrief(
        for day: HelmDay,
        readiness: ReadinessScore?,
        prescriptionSummary: PrescribedSessionSummary?,
        attemptNarration: Bool
    ) async throws -> StoredDailyBrief {
        let settings = try persistence.trainingPlan.load()
        let session = try? await prescriptionEngine.computeSession(for: day, readiness: readiness)
        let bodyMassKg = try persistence.bodyComposition.fetchLatest(onOrBefore: day, limit: 1).first?.mass.kilograms

        let inputs = BriefInputComposer.compose(
            helmDay: day,
            readiness: readiness,
            prescriptionSummary: prescriptionSummary,
            prescriptionSession: session,
            phase: settings.phaseGoal.phase,
            bodyMassKg: bodyMassKg
        )
        let fingerprint = BriefInputFingerprint.compute(from: inputs)

        if let existing = try persistence.brief.fetch(for: day),
           existing.inputFingerprint == fingerprint {
            return existing
        }

        let engineText = BriefEngineTextComposer.compose(from: inputs)
        var narrationText = engineText
        var citationIDs: [String] = []
        var source: BriefNarrationSource = .engineOnly
        var promptVersion: String?
        var schemaVersion: String?

        if attemptNarration {
            let profile = try persistence.memoryProfile.load()
            let evidenceRecords = evidenceRecords(for: inputs.prescription?.evidenceIDs ?? [])
            let prompt = BriefPromptBuilder.build(
                profile: profile,
                inputs: inputs,
                evidenceRecords: evidenceRecords
            )

            do {
                if let artefact = try await narrator.narrate(prompt: prompt) {
                    narrationText = artefact.payload.narration
                    citationIDs = artefact.payload.citationIDs
                    source = .coach
                    promptVersion = artefact.promptVersion.rawValue
                    schemaVersion = artefact.schemaVersion.rawValue
                }
            } catch {
                log.error("Morning brief narration failed: \(String(describing: error), privacy: .public)")
            }
        }

        let brief = StoredDailyBrief(
            helmDay: day,
            inputFingerprint: fingerprint,
            engineText: engineText,
            narrationText: narrationText,
            citationIDs: citationIDs,
            source: source,
            promptVersion: promptVersion,
            schemaVersion: schemaVersion,
            updatedAt: Date()
        )
        try persistence.brief.save(brief)
        return brief
    }

    private func evidenceRecords(for ids: [String]) -> [EvidenceRecord] {
        ids.map { id in
            EvidenceRecord(
                id: id,
                title: id,
                summary: "Referenced by today's prescription.",
                citation: "",
                placeholder: true
            )
        }
    }
}

@MainActor
@Observable
public final class BriefService {
    public private(set) var state: BriefDashboardState = .loading

    private let engine: BriefEngine

    public init(engine: BriefEngine) {
        self.engine = engine
    }

    public func refresh(
        readiness: ReadinessScore?,
        prescriptionSummary: PrescribedSessionSummary?,
        attemptNarration: Bool = true
    ) async {
        let day = HelmDay.day(for: .now, calendar: .current)
        do {
            let brief = try await engine.ensureBrief(
                for: day,
                readiness: readiness,
                prescriptionSummary: prescriptionSummary,
                attemptNarration: attemptNarration
            )
            state = .ready(Self.cardModel(from: brief))
        } catch {
            state = .ready(
                BriefCardModel(
                    narration: "Morning brief unavailable right now.",
                    citationLabel: nil,
                    isEngineOnly: true
                )
            )
        }
    }

    public var briefSummaryForWatch: String? {
        guard case let .ready(model) = state else { return nil }
        let text = model.narration.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        return String(text.prefix(180))
    }

    private static func cardModel(from brief: StoredDailyBrief) -> BriefCardModel {
        let citationLabel: String?
        if brief.citationIDs.isEmpty {
            citationLabel = nil
        } else if brief.citationIDs.count == 1 {
            citationLabel = brief.citationIDs[0]
        } else {
            citationLabel = "\(brief.citationIDs.count) sources"
        }

        return BriefCardModel(
            narration: brief.displayText,
            citationLabel: citationLabel,
            isEngineOnly: brief.source == .engineOnly
        )
    }
}
