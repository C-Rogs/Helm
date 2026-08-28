import Foundation

/// Layout for the nutrition calorie arc: eat-to as the target tick, allowance from
/// baseline plus visualized active energy, logged fill and over on top.
public struct CalorieArcModel: Equatable, Sendable {
    public enum Active: Equatable, Sendable {
        case none
        case syncing
        case partial(Int)
        case fresh(Int)

        public var displayKcal: Int? {
            switch self {
            case .none, .syncing: nil
            case let .partial(kcal), let .fresh(kcal): kcal
            }
        }
    }

    public enum BandKind: String, Sendable {
        case baseline
        case active
    }

    public enum FillKind: String, Sendable {
        case intake
        case over
    }

    public enum Swatch: String, Sendable {
        case baseline
        case active
        case intake
        case over
        case muted
    }

    public enum TickKind: String, Sendable {
        case minor
        case target
        case progress
        case scaleEnd

        public var isMajor: Bool { self != .minor }
    }

    public enum LabelRole: String, Sendable {
        case target
        case progress
        case origin
        case scaleEnd

        var priority: Int {
            switch self {
            case .target: 0
            case .progress: 1
            case .origin: 2
            case .scaleEnd: 3
            }
        }
    }

    public enum LabelAnchor: String, Sendable {
        case gapStart
        case gapEnd
        case radial
    }

    public struct Band: Equatable, Sendable, Identifiable {
        public var id: BandKind { kind }
        public let kind: BandKind
        public let start: Double
        public let end: Double
    }

    public struct Fill: Equatable, Sendable, Identifiable {
        public var id: FillKind { kind }
        public let kind: FillKind
        public let start: Double
        public let end: Double
    }

    public struct Tick: Equatable, Sendable, Identifiable {
        public let id: String
        public let fraction: Double
        public let kind: TickKind
    }

    public struct AttachedLabel: Equatable, Sendable, Identifiable {
        public let id: String
        public let fraction: Double
        public let caption: String?
        public let value: String
        public let anchor: LabelAnchor
        public let role: LabelRole
    }

    public struct LegendItem: Equatable, Sendable, Identifiable {
        public let id: String
        public let label: String
        public let value: String
        public let swatch: Swatch
        public let state: HelmState?
    }

    public let eatToKcal: Int
    public let loggedKcal: Int
    public let hasLogged: Bool
    public let remainingKcal: Int
    public let isOver: Bool
    public let active: Active
    public let visualizedActiveKcal: Int
    public let ceilingKcal: Int
    public let eatToFraction: Double
    public let activeEndFraction: Double
    public let loggedFraction: Double
    public let bands: [Band]
    public let attachedLabels: [AttachedLabel]
    public let ticks: [Tick]
    public let legend: [LegendItem]
    public let fillState: HelmState
    public let centerCaption: String
    public let accessibilityLabel: String

    public var centerValue: Int { abs(remainingKcal) }
    public var showsActiveBand: Bool { visualizedActiveKcal > 0 }

    public var targetLabel: AttachedLabel? {
        attachedLabels.first { $0.role == .target }
    }

    public init(eatToKcal: Int, loggedKcal: Int?, active: Active) {
        let eatTo = max(eatToKcal, 1)
        let logged = max(loggedKcal ?? 0, 0)
        let hasLogged = loggedKcal != nil
        let remaining = eatTo - logged
        let isOver = remaining < 0
        let visualizedActive = Self.visualizedActiveKcal(eatTo: eatTo, active: active)
        let ceiling = max(eatTo + visualizedActive, logged, 1)
        let eatToFraction = Self.fraction(eatTo, of: ceiling)
        let activeEndFraction = Self.fraction(eatTo + visualizedActive, of: ceiling)
        let loggedFraction = Self.fraction(logged, of: ceiling)
        let fillState = Self.fillState(logged: logged, eatTo: eatTo, hasLogged: hasLogged, isOver: isOver)
        let labels = Self.makeAttachedLabels(
            eatTo: eatTo,
            logged: loggedKcal,
            ceiling: ceiling,
            eatToFraction: eatToFraction,
            loggedFraction: loggedFraction
        )

        self.eatToKcal = eatTo
        self.loggedKcal = logged
        self.hasLogged = hasLogged
        self.remainingKcal = remaining
        self.isOver = isOver
        self.active = active
        self.visualizedActiveKcal = visualizedActive
        self.ceilingKcal = ceiling
        self.eatToFraction = eatToFraction
        self.activeEndFraction = activeEndFraction
        self.loggedFraction = loggedFraction
        self.bands = Self.makeBands(
            eatToFraction: eatToFraction,
            activeEndFraction: activeEndFraction,
            visualizedActive: visualizedActive
        )
        self.attachedLabels = labels
        self.ticks = Self.makeTicks(
            ceiling: ceiling,
            labels: labels,
            eatToFraction: eatToFraction
        )
        self.legend = Self.makeLegend(
            logged: loggedKcal,
            isOver: isOver,
            active: active,
            fillState: fillState
        )
        self.fillState = fillState
        self.centerCaption = isOver ? "OVER" : "LEFT"
        self.accessibilityLabel = Self.makeAccessibilityLabel(
            eatTo: eatTo,
            logged: loggedKcal,
            active: active
        )
    }

    public func fills(drawProgress: Double) -> [Fill] {
        let progress = min(max(drawProgress, 0), 1)
        let loggedEnd = loggedFraction * progress
        var result: [Fill] = []
        let inEnd = min(loggedEnd, eatToFraction)
        if inEnd > CalorieArcMetrics.visibleFillEpsilon {
            result.append(Fill(kind: .intake, start: 0, end: inEnd))
        }
        if loggedEnd > eatToFraction + CalorieArcMetrics.visibleFillEpsilon {
            result.append(Fill(kind: .over, start: eatToFraction, end: min(loggedEnd, 1)))
        }
        return result
    }

    public func visibleAttachedLabels(isAccessibilitySize: Bool) -> [AttachedLabel] {
        if isAccessibilitySize {
            return attachedLabels.filter { $0.anchor != .radial }
        }
        return attachedLabels
    }

    public func showsHoleEatTo(isAccessibilitySize: Bool) -> Bool {
        guard isAccessibilitySize else { return false }
        return targetLabel?.anchor == .radial
    }

    public static func compactKcal(_ kcal: Int) -> String {
        if kcal < 1_000 { return "\(kcal)" }
        let tenths = Int((Double(kcal) / 100).rounded())
        if tenths % 10 == 0 {
            return "\(tenths / 10)k"
        }
        return String(format: "%.1fk", Double(tenths) / 10)
    }
}

extension CalorieArcModel {
    private static func fraction(_ value: Int, of ceiling: Int) -> Double {
        guard ceiling > 0 else { return 0 }
        return min(max(Double(value) / Double(ceiling), 0), 1)
    }

    private static func visualizedActiveKcal(eatTo: Int, active: Active) -> Int {
        guard case let .fresh(kcal) = active, kcal > 0 else { return 0 }
        let threshold = max(
            CalorieArcMetrics.minimumActiveKcal,
            Int((Double(eatTo) * CalorieArcMetrics.minimumActiveFractionOfEatTo).rounded())
        )
        return kcal >= threshold ? kcal : 0
    }

    private static func fillState(
        logged: Int,
        eatTo: Int,
        hasLogged: Bool,
        isOver: Bool
    ) -> HelmState {
        if isOver { return .depleted }
        guard hasLogged, logged > 0 else { return .compromised }
        return HelmState.energyBalance(intakeKcal: Double(logged), targetKcal: Double(eatTo))
    }

    private static func makeBands(
        eatToFraction: Double,
        activeEndFraction: Double,
        visualizedActive: Int
    ) -> [Band] {
        var bands: [Band] = [
            Band(kind: .baseline, start: 0, end: eatToFraction)
        ]
        if visualizedActive > 0, activeEndFraction > eatToFraction + CalorieArcMetrics.visibleFillEpsilon {
            bands.append(Band(kind: .active, start: eatToFraction, end: activeEndFraction))
        }
        return bands
    }

    private static func makeAttachedLabels(
        eatTo: Int,
        logged: Int?,
        ceiling: Int,
        eatToFraction: Double,
        loggedFraction: Double
    ) -> [AttachedLabel] {
        var candidates: [AttachedLabel] = [
            makeLabel(
                role: .target,
                fraction: eatToFraction,
                kcal: eatTo,
                caption: "EAT-TO"
            )
        ]

        if let logged, logged > 0 {
            candidates.append(
                makeLabel(
                    role: .progress,
                    fraction: loggedFraction,
                    kcal: logged,
                    caption: nil
                )
            )
        }

        candidates.append(
            makeLabel(role: .origin, fraction: 0, kcal: 0, caption: nil)
        )

        if ceiling > eatTo, 1 - eatToFraction >= CalorieArcMetrics.labelCollisionFraction {
            candidates.append(
                makeLabel(role: .scaleEnd, fraction: 1, kcal: ceiling, caption: nil)
            )
        }

        return resolveCollisions(candidates)
    }

    private static func makeLabel(
        role: LabelRole,
        fraction: Double,
        kcal: Int,
        caption: String?
    ) -> AttachedLabel {
        let anchor = anchor(for: fraction)
        let compact = anchor == .radial
        let hideCaption = caption != nil && CalorieArcMetrics.topCaptionHideRange.contains(fraction)
        return AttachedLabel(
            id: role.rawValue,
            fraction: fraction,
            caption: hideCaption ? nil : caption,
            value: compact ? compactKcal(kcal) : "\(kcal)",
            anchor: anchor,
            role: role
        )
    }

    private static func anchor(for fraction: Double) -> LabelAnchor {
        if fraction <= CalorieArcMetrics.gapStartFraction { return .gapStart }
        if fraction >= CalorieArcMetrics.gapEndFraction { return .gapEnd }
        return .radial
    }

    private static func resolveCollisions(_ candidates: [AttachedLabel]) -> [AttachedLabel] {
        let ranked = candidates.sorted { lhs, rhs in
            if lhs.role.priority != rhs.role.priority {
                return lhs.role.priority < rhs.role.priority
            }
            return lhs.fraction < rhs.fraction
        }
        var kept: [AttachedLabel] = []
        for candidate in ranked {
            let collides = kept.contains {
                abs($0.fraction - candidate.fraction) < CalorieArcMetrics.labelCollisionFraction
            }
            if !collides {
                kept.append(candidate)
            }
        }
        return kept.sorted { $0.fraction < $1.fraction }
    }

    private static func makeTicks(
        ceiling: Int,
        labels: [AttachedLabel],
        eatToFraction: Double
    ) -> [Tick] {
        var ticks: [Tick] = [
            Tick(id: "target", fraction: eatToFraction, kind: .target)
        ]
        for label in labels where label.role != .target && label.role != .origin {
            let kind: TickKind = label.role == .progress ? .progress : .scaleEnd
            ticks.append(Tick(id: kind.rawValue, fraction: label.fraction, kind: kind))
        }

        let majors = ticks.map(\.fraction)
        if let step = minorStep(ceiling: ceiling) {
            var value = step
            var index = 0
            while value < ceiling {
                let fraction = Self.fraction(value, of: ceiling)
                let collides = majors.contains {
                    abs($0 - fraction) < CalorieArcMetrics.tickCollisionFraction
                }
                if !collides, fraction > 0.04, fraction < 0.96 {
                    ticks.append(Tick(id: "minor-\(index)", fraction: fraction, kind: .minor))
                    index += 1
                }
                value += step
            }
        }

        return ticks.sorted { $0.fraction < $1.fraction }
    }

    private static func minorStep(ceiling: Int) -> Int? {
        switch ceiling {
        case ..<1_000: nil
        case ..<2_500: 500
        case ..<6_000: 1_000
        default: 2_000
        }
    }

    private static func makeLegend(
        logged: Int?,
        isOver: Bool,
        active: Active,
        fillState: HelmState
    ) -> [LegendItem] {
        var items: [LegendItem] = []

        switch active {
        case .none:
            break
        case .syncing:
            items.append(
                LegendItem(
                    id: "active",
                    label: "ACTIVE",
                    value: "SYNC",
                    swatch: .muted,
                    state: .compromised
                )
            )
        case let .partial(kcal):
            items.append(
                LegendItem(
                    id: "active",
                    label: "ACTIVE",
                    value: "\(max(kcal, 0))",
                    swatch: .muted,
                    state: .compromised
                )
            )
        case let .fresh(kcal):
            items.append(
                LegendItem(
                    id: "active",
                    label: "ACTIVE",
                    value: "\(max(kcal, 0))",
                    swatch: .active,
                    state: nil
                )
            )
        }

        items.append(
            LegendItem(
                id: "in",
                label: "IN",
                value: logged.map { "\($0)" } ?? "-",
                swatch: isOver ? .over : .intake,
                state: logged == nil ? nil : fillState
            )
        )
        return items
    }

    private static func makeAccessibilityLabel(
        eatTo: Int,
        logged: Int?,
        active: Active
    ) -> String {
        let remaining = eatTo - (logged ?? 0)
        var parts: [String] = []
        if remaining < 0 {
            parts.append("\(abs(remaining)) kilocalories over eat-to")
        } else {
            parts.append("\(remaining) kilocalories left")
        }
        parts.append("Eat-to \(eatTo) kilocalories")
        if let logged {
            parts.append("\(logged) logged")
        } else {
            parts.append("Nothing logged")
        }
        switch active {
        case .none:
            break
        case .syncing:
            parts.append("Active energy syncing")
        case let .partial(kcal):
            parts.append("Active energy \(kcal) kilocalories, still catching up")
        case let .fresh(kcal):
            parts.append("Active energy \(kcal) kilocalories, not in eat-to")
        }
        return parts.joined(separator: ". ")
    }
}

enum CalorieArcMetrics {
    static let minimumActiveKcal = 80
    static let minimumActiveFractionOfEatTo = 0.04
    static let gapStartFraction = 0.04
    static let gapEndFraction = 0.96
    static let labelCollisionFraction = 0.11
    static let tickCollisionFraction = 0.08
    static let visibleFillEpsilon = 0.004
    static let topCaptionHideRange = 0.32 ... 0.68
}
