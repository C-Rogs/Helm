import Foundation

/// Last HealthKit body-fat probe. Dates, counts, skip reasons. No sample values.
public struct BodyFatQueryTrace: Sendable, Equatable {
    public let probedAt: Date?
    public let hkSampleCount: Int
    public let newestHkDay: String?
    public let storedDay: String?
    public let keptCount: Int
    public let skippedOwnSource: Int
    public let skippedIncompatibleUnit: Int
    public let skippedOutOfRange: Int
    public let skippedNotQuantity: Int
    public let overlayError: String?
    public let queryError: String?
    public let sources: String
    public let lag: String
    public let stage: String

    public init(
        probedAt: Date?,
        hkSampleCount: Int,
        newestHkDay: String?,
        storedDay: String?,
        keptCount: Int,
        skippedOwnSource: Int,
        skippedIncompatibleUnit: Int,
        skippedOutOfRange: Int,
        skippedNotQuantity: Int,
        overlayError: String?,
        queryError: String?,
        sources: String,
        lag: String,
        stage: String
    ) {
        self.probedAt = probedAt
        self.hkSampleCount = hkSampleCount
        self.newestHkDay = newestHkDay
        self.storedDay = storedDay
        self.keptCount = keptCount
        self.skippedOwnSource = skippedOwnSource
        self.skippedIncompatibleUnit = skippedIncompatibleUnit
        self.skippedOutOfRange = skippedOutOfRange
        self.skippedNotQuantity = skippedNotQuantity
        self.overlayError = overlayError
        self.queryError = queryError
        self.sources = sources
        self.lag = lag
        self.stage = stage
    }

    public static let empty = BodyFatQueryTrace(
        probedAt: nil,
        hkSampleCount: 0,
        newestHkDay: nil,
        storedDay: nil,
        keptCount: 0,
        skippedOwnSource: 0,
        skippedIncompatibleUnit: 0,
        skippedOutOfRange: 0,
        skippedNotQuantity: 0,
        overlayError: nil,
        queryError: nil,
        sources: "none",
        lag: "unprobed",
        stage: "none"
    )

    public var hasSkips: Bool {
        skippedOwnSource + skippedIncompatibleUnit + skippedOutOfRange + skippedNotQuantity > 0
    }

    public var diagnosticContext: [String: String] {
        var context: [String: String] = [
            "stage": stage,
            "hkCount": String(hkSampleCount),
            "kept": String(keptCount),
            "newestHkDay": newestHkDay ?? "none",
            "storedDay": storedDay ?? "none",
            "lag": lag,
            "sources": sources,
            "skipOwn": String(skippedOwnSource),
            "skipUnit": String(skippedIncompatibleUnit),
            "skipRange": String(skippedOutOfRange),
            "skipType": String(skippedNotQuantity),
        ]
        if let overlayError {
            context["overlayError"] = String(overlayError.prefix(160))
        }
        if let queryError {
            context["queryError"] = String(queryError.prefix(160))
        }
        return context
    }

    public var logLine: String {
        diagnosticContext
            .map { "\($0.key)=\($0.value)" }
            .sorted()
            .joined(separator: " ")
    }

    public static func lag(newestHkDay: String?, storedDay: String?) -> String {
        switch (newestHkDay, storedDay) {
        case (nil, nil):
            "both_empty"
        case (nil, _):
            "hk_empty"
        case (_, nil):
            "store_empty"
        case let (hk?, stored?) where hk > stored:
            "hk_ahead"
        case let (hk?, stored?) where hk < stored:
            "store_ahead"
        default:
            "in_sync"
        }
    }
}

/// Newest readable HealthKit body-fat percent plus newest stored row. For coach copy, not the ring buffer.
public struct BodyFatLatestFacts: Sendable, Equatable {
    public let hkDay: String?
    public let hkPercent: Double?
    public let storeDay: String?
    public let storePercent: Double?
    public let hkReadableCount: Int
    public let hkSource: String?

    public init(
        hkDay: String?,
        hkPercent: Double?,
        storeDay: String?,
        storePercent: Double?,
        hkReadableCount: Int,
        hkSource: String? = nil
    ) {
        self.hkDay = hkDay
        self.hkPercent = hkPercent
        self.storeDay = storeDay
        self.storePercent = storePercent
        self.hkReadableCount = hkReadableCount
        self.hkSource = hkSource
    }

    public static let empty = BodyFatLatestFacts(
        hkDay: nil,
        hkPercent: nil,
        storeDay: nil,
        storePercent: nil,
        hkReadableCount: 0
    )

    /// Always returns copy. Empty HealthKit means the source never wrote Body Fat Percentage
    /// (or Signal cannot read that source), not that the query window is wrong.
    public func groundedChatReply() -> String {
        var parts: [String] = []
        if let hkDay, let hkPercent {
            var line = "Apple Health newest Body Fat Percentage sample this app can read is \(Self.format(hkPercent))% on \(hkDay)."
            if let hkSource {
                line += " Source \(hkSource)."
            }
            parts.append(line)
        } else {
            parts.append(
                "Apple Health has no Body Fat Percentage sample this app can read. If you just used a scale, confirm it wrote that type to Health, then check Settings, Apple Health, Body fat probe."
            )
        }
        if let storeDay, let storePercent {
            let same = storeDay == hkDay && storePercent == hkPercent
            if !same {
                parts.append("Signal store has \(Self.format(storePercent))% on \(storeDay).")
            }
        }
        return parts.joined(separator: " ")
    }

    private static func format(_ value: Double) -> String {
        String(format: "%.1f", value)
    }
}
