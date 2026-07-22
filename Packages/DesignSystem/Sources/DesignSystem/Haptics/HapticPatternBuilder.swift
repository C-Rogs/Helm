import CoreHaptics
import Foundation
import UIKit

public enum HapticFallback: Sendable {
    case selection
    case impact(UIImpactFeedbackGenerator.FeedbackStyle)
    case notification(UINotificationFeedbackGenerator.FeedbackType)

    @MainActor
    func fire() {
        switch self {
        case .selection:
            UISelectionFeedbackGenerator().selectionChanged()
        case let .impact(style):
            UIImpactFeedbackGenerator(style: style).impactOccurred()
        case let .notification(type):
            UINotificationFeedbackGenerator().notificationOccurred(type)
        }
    }
}

public enum HapticFallbackResolver {
    public static func fallback(for pattern: HelmHaptic) -> HapticFallback {
        switch pattern {
        case .readinessReveal, .phaseChange, .prHit, .sessionFinished:
            .notification(.success)
        case .thresholdInsight:
            .impact(.soft)
        case .setLogged:
            .impact(.rigid)
        case .restCountIn:
            .impact(.light)
        case .restDone:
            .notification(.warning)
        case .mealConfirmed, .coachAdjust:
            .impact(.soft)
        case .clampRejected:
            .notification(.error)
        case .selection:
            .selection
        }
    }
}

enum HapticPatternBuilder {
    static func pattern(for helmPattern: HelmHaptic, lowPowerMode: Bool) throws -> CHHapticPattern {
        switch helmPattern {
        case .readinessReveal:
            return try readinessReveal(lowPowerMode: lowPowerMode)
        case .phaseChange:
            return try phaseChange()
        case .thresholdInsight:
            return try thresholdInsight(lowPowerMode: lowPowerMode)
        case .setLogged:
            return try transient(intensity: 0.8, sharpness: 0.9)
        case .restCountIn:
            return try restCountIn()
        case .restDone:
            return try restDone()
        case .prHit:
            return try prHit()
        case .sessionFinished:
            return try sessionFinished()
        case .mealConfirmed:
            return try transient(intensity: 0.5, sharpness: 0.2)
        case .coachAdjust:
            return try coachAdjust()
        case .clampRejected:
            return try clampRejected()
        case .selection:
            return try transient(intensity: 0.35, sharpness: 0.4)
        }
    }

    private static func transient(intensity: Float, sharpness: Float, at time: TimeInterval = 0) throws -> CHHapticPattern {
        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
            ],
            relativeTime: time
        )
        return try CHHapticPattern(events: [event], parameters: [])
    }

    private static func readinessReveal(lowPowerMode: Bool) throws -> CHHapticPattern {
        if lowPowerMode {
            return try transient(intensity: 0.9, sharpness: 0.4, at: 0.7)
        }

        let swell = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.2),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
            ],
            relativeTime: 0,
            duration: 0.7
        )
        let crest = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
            ],
            relativeTime: 0.7
        )
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.2),
                .init(relativeTime: 0.7, value: 0.7)
            ],
            relativeTime: 0
        )
        return try CHHapticPattern(events: [swell, crest], parameterCurves: [curve])
    }

    private static func phaseChange() throws -> CHHapticPattern {
        let events = [0.0, 0.12, 0.24].map { time in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                ],
                relativeTime: time
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    private static func thresholdInsight(lowPowerMode: Bool) throws -> CHHapticPattern {
        if lowPowerMode {
            return try transient(intensity: 0.2, sharpness: 0.2)
        }
        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.15),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
            ],
            relativeTime: 0,
            duration: 0.35
        )
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0, value: 0.15),
                .init(relativeTime: 0.35, value: 0.3)
            ],
            relativeTime: 0
        )
        return try CHHapticPattern(events: [event], parameterCurves: [curve])
    }

    private static func restCountIn() throws -> CHHapticPattern {
        let intensities: [Float] = [0.4, 0.5, 0.6]
        let events = intensities.enumerated().map { index, intensity in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: TimeInterval(index) * 0.3
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    private static func restDone() throws -> CHHapticPattern {
        let events = [0.0, 0.12].map { time in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.8)
                ],
                relativeTime: time
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    private static func prHit() throws -> CHHapticPattern {
        let specs: [(Float, Float, TimeInterval)] = [
            (0.7, 0.5, 0),
            (0.85, 0.6, 0.09),
            (1.0, 0.8, 0.18)
        ]
        let events = specs.map { intensity, sharpness, time in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness)
                ],
                relativeTime: time
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    private static func sessionFinished() throws -> CHHapticPattern {
        let hit = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.9),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.7)
            ],
            relativeTime: 0
        )
        let settle = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
            ],
            relativeTime: 0.05,
            duration: 0.4
        )
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                .init(relativeTime: 0.05, value: 0.5),
                .init(relativeTime: 0.45, value: 0)
            ],
            relativeTime: 0
        )
        return try CHHapticPattern(events: [hit, settle], parameterCurves: [curve])
    }

    private static func coachAdjust() throws -> CHHapticPattern {
        let events = [0.0, 0.1].map { time in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.5),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.3)
                ],
                relativeTime: time
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }

    private static func clampRejected() throws -> CHHapticPattern {
        let events = [0.0, 0.05].map { time in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: time == 0 ? 1.0 : 0.7),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ],
                relativeTime: time
            )
        }
        return try CHHapticPattern(events: events, parameters: [])
    }
}
