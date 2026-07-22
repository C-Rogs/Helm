import CoreHaptics
import Diagnostics
import Foundation
import UIKit

@MainActor
public protocol HapticPlaying {
    var supportsHaptics: Bool { get }
    func play(_ pattern: HelmHaptic, lowPowerMode: Bool) async
}

@MainActor
public final class HapticEngine: HapticPlaying {
    public static let shared = HapticEngine()

    private let hardware: HapticHardware
    private let preferences: HelmThemeCoordinator
    private let processInfo: ProcessInfo

    public var supportsHaptics: Bool { hardware.supportsHaptics }

    init(
        hardware: HapticHardware = SystemHapticHardware(),
        preferences: HelmThemeCoordinator = .shared,
        processInfo: ProcessInfo = .processInfo
    ) {
        self.hardware = hardware
        self.preferences = preferences
        self.processInfo = processInfo
    }

    public func play(_ pattern: HelmHaptic) {
        guard preferences.hapticsEnabled else { return }
        Task {
            await play(pattern, lowPowerMode: processInfo.isLowPowerModeEnabled)
        }
    }

    public func play(_ pattern: HelmHaptic, lowPowerMode: Bool) async {
        guard preferences.hapticsEnabled else { return }

        if hardware.supportsHaptics {
            do {
                try await hardware.playBuiltPattern(pattern, lowPowerMode: lowPowerMode)
                return
            } catch {
                await logFailure(pattern: pattern, error: error, phase: "built-pattern")
            }

            if let resourceName = pattern.resourceName,
               let url = Bundle.module.url(forResource: resourceName, withExtension: "ahap") {
                do {
                    try await hardware.playAHAP(at: url, lowPowerMode: lowPowerMode)
                    return
                } catch {
                    await logFailure(pattern: pattern, error: error, phase: "ahap")
                }
            }
        }

        await playFallback(pattern)
    }

    private func playFallback(_ pattern: HelmHaptic) async {
        let fallback = HapticFallbackResolver.fallback(for: pattern)
        switch pattern {
        case .restCountIn:
            fallback.fire()
            try? await Task.sleep(for: .milliseconds(300))
            fallback.fire()
            try? await Task.sleep(for: .milliseconds(300))
            fallback.fire()
        case .coachAdjust:
            fallback.fire()
            try? await Task.sleep(for: .milliseconds(100))
            fallback.fire()
        default:
            fallback.fire()
        }
    }

    private func logFailure(pattern: HelmHaptic, error: Error, phase: String) async {
        await DiagnosticsLog.shared.capture(
            error: error,
            category: .ui,
            message: "HapticEngine \(phase) failed",
            context: ["pattern": pattern.rawValue]
        )
    }
}

@MainActor
protocol HapticHardware {
    var supportsHaptics: Bool { get }
    func playBuiltPattern(_ pattern: HelmHaptic, lowPowerMode: Bool) async throws
    func playAHAP(at url: URL, lowPowerMode: Bool) async throws
}

@MainActor
final class SystemHapticHardware: HapticHardware {
    private var engine: CHHapticEngine?

    var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    func playBuiltPattern(_ pattern: HelmHaptic, lowPowerMode: Bool) async throws {
        let hapticPattern = try HapticPatternBuilder.pattern(for: pattern, lowPowerMode: lowPowerMode)
        try await play(pattern: hapticPattern)
    }

    func playAHAP(at url: URL, lowPowerMode: Bool) async throws {
        let hapticPattern = try CHHapticPattern(contentsOf: url)
        if lowPowerMode, Self.isContinuousAHAP(url) {
            throw HapticEngineError.lowPowerContinuousSkipped
        }
        try await play(pattern: hapticPattern)
    }

    private func play(pattern: CHHapticPattern) async throws {
        let engine = try await preparedEngine()
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: 0)
    }

    private func preparedEngine() async throws -> CHHapticEngine {
        if let engine {
            return engine
        }

        guard supportsHaptics else {
            throw HapticEngineError.hardwareUnavailable
        }

        let created = try CHHapticEngine()
        created.stoppedHandler = { [weak self] reason in
            Task { @MainActor in
                await self?.handleStopped(reason: reason)
            }
        }
        created.resetHandler = { [weak self] in
            Task { @MainActor in
                await self?.handleReset()
            }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            created.start { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
        engine = created
        return created
    }

    private func handleStopped(reason: CHHapticEngine.StoppedReason) async {
        engine = nil
        await DiagnosticsLog.shared.record(
            category: .ui,
            level: .error,
            message: "CHHapticEngine stopped",
            context: ["reason": String(describing: reason)]
        )
    }

    private func handleReset() async {
        engine = nil
        await DiagnosticsLog.shared.record(
            category: .ui,
            level: .info,
            message: "CHHapticEngine reset"
        )
    }

    private static func isContinuousAHAP(_ url: URL) -> Bool {
        let name = url.deletingPathExtension().lastPathComponent
        return ["readinessReveal", "thresholdInsight", "sessionFinished"].contains(name)
    }
}

enum HapticEngineError: Error {
    case hardwareUnavailable
    case lowPowerContinuousSkipped
}

/// Test double for agent-verifiable haptic behavior.
@MainActor
public final class MockHapticHardware: HapticHardware {
    public private(set) var playedPatterns: [HelmHaptic] = []
    public private(set) var playedAHAPs: [URL] = []
    public var supportsHapticsValue = true
    public var builtPatternError: Error?
    public var ahapError: Error?

    public var supportsHaptics: Bool { supportsHapticsValue }

    public init() {}

    public func playBuiltPattern(_ pattern: HelmHaptic, lowPowerMode: Bool) async throws {
        if let builtPatternError { throw builtPatternError }
        playedPatterns.append(pattern)
    }

    public func playAHAP(at url: URL, lowPowerMode: Bool) async throws {
        if let ahapError { throw ahapError }
        playedAHAPs.append(url)
    }
}

