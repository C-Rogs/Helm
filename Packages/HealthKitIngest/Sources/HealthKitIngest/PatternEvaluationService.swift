import CoachLLM
import Core
import Diagnostics
import Foundation
import PatternKit
import Persistence

public struct PatternEvaluationOptions: Sendable {
    public var runTypedSearch: Bool
    public var proposed: [HypothesisSpec]
    public var useOnlineFDR: Bool
    /// Skip ContrastEngine when the assembled matrix signature is unchanged.
    public var skipIfMatrixUnchanged: Bool

    public init(
        runTypedSearch: Bool = false,
        proposed: [HypothesisSpec] = [],
        useOnlineFDR: Bool = false,
        skipIfMatrixUnchanged: Bool = true
    ) {
        self.runTypedSearch = runTypedSearch
        self.proposed = proposed
        self.useOnlineFDR = useOnlineFDR
        self.skipIfMatrixUnchanged = skipIfMatrixUnchanged
    }
}

enum PatternEvaluateMetadata {
    static let matrixSignatureKey = "pattern.matrix.signature"
    static let newlyStableHeadlineKey = "pattern.newly_stable.headline"
    static let newlyStableDayKey = "pattern.newly_stable.day"
}

public struct PatternEvaluationService: Sendable {
    private let store: PersistenceStore
    private let calendar: Calendar
    private let cutoff: DayCutoff
    private let signpost: HelmSignpost

    public init(
        store: PersistenceStore,
        calendar: Calendar = .current,
        cutoff: DayCutoff = .default
    ) {
        self.store = store
        self.calendar = calendar
        self.cutoff = cutoff
        signpost = HelmSignpost(name: .patternEvaluate, category: .patternKit)
    }

    @discardableResult
    public func evaluate(
        options: PatternEvaluationOptions = PatternEvaluationOptions(),
        rows assembledRows: [DayFeatureRow]? = nil
    ) throws -> [PatternFinding] {
        let signpostID = signpost.makeSignpostID()
        signpost.begin(id: signpostID)
        defer { signpost.end(id: signpostID) }

        let rows = try assembledRows ?? DayFeatureAssembler.assemble(
            from: store,
            calendar: calendar,
            cutoff: cutoff
        )
        let signature = Self.matrixSignature(rows)
        let discovering = options.runTypedSearch || !options.proposed.isEmpty
        if options.skipIfMatrixUnchanged, !discovering {
            if (try? store.appMetadata.value(forKey: PatternEvaluateMetadata.matrixSignatureKey)) == signature {
                return try storedFindings()
            }
        }

        let previousStored = (try? store.patternFindings.fetchAll()) ?? []
        let previousPairs = previousStored.compactMap { stored -> (String, PatternFinding)? in
            (try? PatternFindingCodec.finding(from: stored)).map { ($0.id, $0) }
        }
        let previous = Dictionary(previousPairs, uniquingKeysWith: { _, last in last })

        var specs = SeedCatalog.all
        var seenIDs = Set(specs.map { HypothesisCompiler.canonicalID(for: $0) })
        var seenAST = Set(specs.map { HypothesisCompiler.astKey($0) })
        for finding in previous.values {
            let key = HypothesisCompiler.astKey(finding.spec)
            guard seenAST.insert(key).inserted else { continue }
            specs.append(finding.spec)
            seenIDs.insert(HypothesisCompiler.canonicalID(for: finding.spec))
        }
        if options.runTypedSearch {
            let extra = TypedHypothesisSearch.candidates(
                rows: rows,
                existingIDs: seenIDs.union(seenAST)
            )
            for spec in extra {
                let id = HypothesisCompiler.canonicalID(for: spec)
                let key = HypothesisCompiler.astKey(spec)
                guard seenIDs.insert(id).inserted, seenAST.insert(key).inserted else { continue }
                specs.append(spec)
            }
        }
        for proposal in options.proposed.prefix(PatternKit.proposeCap) {
            switch HypothesisCompiler.compile(proposal) {
            case .success(let spec):
                let id = HypothesisCompiler.canonicalID(for: spec)
                let key = HypothesisCompiler.astKey(spec)
                if seenIDs.insert(id).inserted, seenAST.insert(key).inserted {
                    specs.append(spec)
                }
            case .failure:
                continue
            }
        }

        var fdrState: LORDPlusPlusState? = nil
        var lastDiscovery = (try? store.patternFindings.loadFDRState())?.lastDiscoveryAt
        if options.useOnlineFDR {
            if let stored = try store.patternFindings.loadFDRState() {
                fdrState = PatternFindingCodec.fdrState(from: stored)
                lastDiscovery = stored.lastDiscoveryAt
            } else {
                fdrState = LORDPlusPlusState()
            }
        }

        let (findings, nextFDR) = ContrastEngine.evaluateCatalog(
            rows: rows,
            specs: specs,
            previous: previous,
            sequentialFDR: fdrState
        )
        try store.patternFindings.upsertAll(findings.map { try PatternFindingCodec.stored(from: $0) })
        try recordNewlyStable(findings: findings, previous: previous, now: Date())
        try store.appMetadata.setValue(signature, forKey: PatternEvaluateMetadata.matrixSignatureKey)
        if let nextFDR {
            if discovering {
                lastDiscovery = Date()
            }
            try store.patternFindings.saveFDRState(
                try PatternFindingCodec.stored(from: nextFDR, lastDiscoveryAt: lastDiscovery)
            )
        }
        return findings
    }

    public func refresh(isCharging: Bool, forceDiscovery: Bool = false, now: Date = Date()) async {
        var options = PatternEvaluationOptions()
        let last = try? lastDiscoveryAt()
        let stale = last.map { now.timeIntervalSince($0) > 7 * 86_400 } ?? true
        let rows = try? DayFeatureAssembler.assemble(from: store, calendar: calendar, cutoff: cutoff)
        if (isCharging || forceDiscovery), stale {
            options.runTypedSearch = true
            options.useOnlineFDR = true
            options.skipIfMatrixUnchanged = false
            options.proposed = await PatternDiscoveryClient.propose(store: store, rows: rows)
        }
        _ = try? evaluate(options: options, rows: rows)
    }

    public func storedFindings(statuses: [FindingStatus]? = nil) throws -> [PatternFinding] {
        let stored: [StoredPatternFinding]
        if let statuses {
            stored = try store.patternFindings.fetch(statuses: statuses.map(\.rawValue))
        } else {
            stored = try store.patternFindings.fetchAll()
        }
        return stored.compactMap { try? PatternFindingCodec.finding(from: $0) }
    }

    public func confirmToMemory(id: String) throws {
        try store.patternFindings.markMemoryConfirmed(id: id)
        guard let stored = try store.patternFindings.fetch(id: id),
              let finding = try? PatternFindingCodec.finding(from: stored)
        else { return }
        var profile = try store.memoryProfile.load()
        let line = finding.headline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else { return }
        if isNutritionPattern(finding.spec) {
            profile.nutritionPatterns = appendMemoryLine(profile.nutritionPatterns, line)
        } else {
            profile.trainingResponses = appendMemoryLine(profile.trainingResponses, line)
        }
        try store.memoryProfile.save(profile)
    }

    public func lastDiscoveryAt() throws -> Date? {
        try store.patternFindings.loadFDRState()?.lastDiscoveryAt
    }

    public func schemaSummary() throws -> String {
        let rows = try DayFeatureAssembler.assemble(from: store, calendar: calendar, cutoff: cutoff)
        return FeatureCoverageSummary.schemaPromptLines(rows)
    }

    public func cardModels() throws -> [PatternFindingCardModel] {
        try storedFindings()
            .filter { $0.status != .retired }
            .sorted { cardRank($0.status) < cardRank($1.status) }
            .map { finding in
                PatternFindingCardModel(
                    id: finding.id,
                    statusLabel: statusLabel(finding.status),
                    copyRegisterLabel: finding.copyRegister.rawValue.replacingOccurrences(of: "_", with: " ").uppercased(),
                    headline: finding.headline,
                    body: finding.body,
                    nExp: finding.nExp,
                    nCtrl: finding.nCtrl,
                    cliffsDelta: finding.cliffsDelta,
                    medianDelta: finding.medianDelta,
                    canConfirmToMemory: finding.status == .stable || finding.status == .emerging
                )
            }
    }

    /// Emerging or stable personal associations. Priors stay off the Chat chip.
    public func hasNarratableFindings() throws -> Bool {
        try storedFindings().contains {
            $0.status == .emerging || $0.status == .stable || $0.status == .memoryConfirmed
        }
    }

    public func stableBriefLine(today: HelmDay? = nil) -> String? {
        let day = today ?? HelmDay.day(for: Date(), cutoff: cutoff, calendar: calendar)
        guard let storedDay = try? store.appMetadata.value(forKey: PatternEvaluateMetadata.newlyStableDayKey),
              storedDay == day.formatted,
              let headline = try? store.appMetadata.value(forKey: PatternEvaluateMetadata.newlyStableHeadlineKey)
        else {
            return nil
        }
        let trimmed = headline.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasSuffix(".") {
            return "Pattern: \(trimmed)"
        }
        return "Pattern: \(trimmed)."
    }

    private func recordNewlyStable(
        findings: [PatternFinding],
        previous: [String: PatternFinding],
        now: Date
    ) throws {
        let promoted = findings.filter { finding in
            guard finding.status == .stable else { return false }
            let prior = previous[finding.id]?.status
            return prior != .stable && prior != .memoryConfirmed
        }
        let day = HelmDay.day(for: now, cutoff: cutoff, calendar: calendar)
        if let first = promoted.first {
            try store.appMetadata.setValue(first.headline, forKey: PatternEvaluateMetadata.newlyStableHeadlineKey)
            try store.appMetadata.setValue(day.formatted, forKey: PatternEvaluateMetadata.newlyStableDayKey)
        } else if (try? store.appMetadata.value(forKey: PatternEvaluateMetadata.newlyStableDayKey)) != day.formatted {
            try store.appMetadata.setValue(nil, forKey: PatternEvaluateMetadata.newlyStableHeadlineKey)
            try store.appMetadata.setValue(nil, forKey: PatternEvaluateMetadata.newlyStableDayKey)
        }
    }

    static func matrixSignature(_ rows: [DayFeatureRow]) -> String {
        let last = rows.last?.helmDay.formatted ?? "none"
        let diet = rows.compactMap(\.dietEnergyKcal).count
        let sleep = rows.compactMap(\.sleepAsleepMin).count
        let alcohol = rows.compactMap(\.alcohol).count
        return "\(rows.count)|\(last)|\(diet)|\(sleep)|\(alcohol)"
    }

    private func cardRank(_ status: FindingStatus) -> Int {
        switch status {
        case .stable: 0
        case .memoryConfirmed: 1
        case .emerging: 2
        case .priorSeed: 3
        case .retired: 4
        }
    }

    private func statusLabel(_ status: FindingStatus) -> String {
        switch status {
        case .priorSeed: "PRIOR"
        case .emerging: "EMERGING"
        case .stable: "STABLE"
        case .retired: "RETIRED"
        case .memoryConfirmed: "MEMORY"
        }
    }

    private func isNutritionPattern(_ spec: HypothesisSpec) -> Bool {
        nutritionFields.contains(spec.exposure.field) || nutritionFields.contains(spec.outcome.field)
    }

    private var nutritionFields: Set<DayFeatureField> {
        [
            .alcohol,
            .breakfastLogged,
            .dietEnergyKcal,
            .dietProteinG,
            .energyResidual,
            .bodyMassKg
        ]
    }

    private func appendMemoryLine(_ existing: String, _ line: String) -> String {
        let trimmed = existing.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return line }
        if trimmed.contains(line) { return existing }
        return trimmed + "\n" + line
    }
}

public struct PatternFindingCardModel: Sendable, Equatable, Identifiable {
    public let id: String
    public let statusLabel: String
    public let copyRegisterLabel: String
    public let headline: String
    public let body: String
    public let nExp: Int
    public let nCtrl: Int
    public let cliffsDelta: Double?
    public let medianDelta: Double?
    public let canConfirmToMemory: Bool

    public init(
        id: String,
        statusLabel: String,
        copyRegisterLabel: String,
        headline: String,
        body: String,
        nExp: Int,
        nCtrl: Int,
        cliffsDelta: Double?,
        medianDelta: Double?,
        canConfirmToMemory: Bool
    ) {
        self.id = id
        self.statusLabel = statusLabel
        self.copyRegisterLabel = copyRegisterLabel
        self.headline = headline
        self.body = body
        self.nExp = nExp
        self.nCtrl = nCtrl
        self.cliffsDelta = cliffsDelta
        self.medianDelta = medianDelta
        self.canConfirmToMemory = canConfirmToMemory
    }
}
