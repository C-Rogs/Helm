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
    private let feedbackPool: HapticFeedbackPool

    public var supportsHaptics: Bool { hardware.supportsHaptics }

    init(
        hardware: HapticHardware = SystemHapticHardware(),
        preferences: HelmThemeCoordinator = .shared,
        processInfo: ProcessInfo = .processInfo,
        feedbackPool: HapticFeedbackPool = HapticFeedbackPool()
    ) {
        self.hardware = hardware
        self.preferences = preferences
        self.processInfo = processInfo
        self.feedbackPool = feedbackPool
    }

    /// Warm UIKit generators and start Core Haptics so the first tap is not a cold start.
    public func prepare() {
        guard preferences.hapticsEnabled else { return }
        feedbackPool.prepare()
        Task { @MainActor in
            try? await hardware.warmUp()
        }
    }

    public func play(_ pattern: HelmHaptic) {
        guard preferences.hapticsEnabled else { return }

        if pattern.playsOnSameFrame {
            if Thread.isMainThread {
                playSameFrame(pattern)
            } else {
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated {
                        self?.playSameFrame(pattern)
                    }
                }
            }
            return
        }

        // CoreHaptics can resume off-main; hop to the real main queue.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in
                await self.play(pattern, lowPowerMode: self.processInfo.isLowPowerModeEnabled)
            }
        }
    }

    private func playSameFrame(_ pattern: HelmHaptic) {
        if pattern == .selection {
            feedbackPool.fire(.selection)
            return
        }
        if hardware.playBuiltPatternImmediately(pattern, lowPowerMode: processInfo.isLowPowerModeEnabled) {
            return
        }
        feedbackPool.fire(HapticFallbackResolver.fallback(for: pattern))
        Task { @MainActor in
            try? await hardware.warmUp()
        }
    }

    public func play(_ pattern: HelmHaptic, lowPowerMode: Bool) async {
        guard preferences.hapticsEnabled else { return }

        if hardware.supportsHaptics {
            do {
                try await hardware.playBuiltPattern(pattern, lowPowerMode: lowPowerMode)
                return
            } catch {
                hardware.invalidate()
                await logFailure(pattern: pattern, error: error, phase: "built-pattern")
            }

            if let resourceName = pattern.resourceName,
               let url = Bundle.module.url(forResource: resourceName, withExtension: "ahap") {
                do {
                    try await hardware.playAHAP(at: url, lowPowerMode: lowPowerMode)
                    return
                } catch {
                    hardware.invalidate()
                    await logFailure(pattern: pattern, error: error, phase: "ahap")
                }
            }
        }

        await playFallback(pattern)
    }

    private func playFallback(_ pattern: HelmHaptic) async {
        let fallback = HapticFallbackResolver.fallback(for: pattern)
        switch pattern {
        case .coachAdjust:
            feedbackPool.fire(fallback)
            try? await Task.sleep(for: .milliseconds(100))
            feedbackPool.fire(fallback)
        default:
            feedbackPool.fire(fallback)
        }
    }

    private func logFailure(pattern: HelmHaptic, error: Error, phase: String) async {
        await DiagnosticsLog.shared.capture(
            error: error,
            category: .ui,
            message: "HapticEngine \(phase) failed",
            context: ["pattern": pattern.diagnosticName]
        )
    }
}

@MainActor
protocol HapticHardware {
    var supportsHaptics: Bool { get }
    var isEngineReady: Bool { get }
    func playBuiltPattern(_ pattern: HelmHaptic, lowPowerMode: Bool) async throws
    func playAHAP(at url: URL, lowPowerMode: Bool) async throws
    func playBuiltPatternImmediately(_ pattern: HelmHaptic, lowPowerMode: Bool) -> Bool
    func warmUp() async throws
    func invalidate()
}

@MainActor
final class SystemHapticHardware: HapticHardware {
    private var engine: CHHapticEngine?

    var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }

    var isEngineReady: Bool { engine != nil }

    func invalidate() {
        engine = nil
    }

    func warmUp() async throws {
        _ = try await preparedEngine()
    }

    func playBuiltPatternImmediately(_ pattern: HelmHaptic, lowPowerMode: Bool) -> Bool {
        guard engine != nil else { return false }
        guard let hapticPattern = try? HapticPatternBuilder.pattern(for: pattern, lowPowerMode: lowPowerMode) else {
            return false
        }
        return start(hapticPattern)
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
        let needsReclaim = engine == nil
        let engine = try await preparedEngine()
        if needsReclaim {
            await reclaimMainThread()
        }
        let player = try engine.makePlayer(with: pattern)
        try player.start(atTime: 0)
    }

    private func start(_ pattern: CHHapticPattern) -> Bool {
        guard let engine else { return false }
        do {
            let player = try engine.makePlayer(with: pattern)
            try player.start(atTime: 0)
            return true
        } catch {
            invalidate()
            return false
        }
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
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                created.start { error in
                    // CoreHaptics completion is off-main; resume on the real main queue.
                    DispatchQueue.main.async {
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume()
                        }
                    }
                }
            }
        } catch {
            engine = nil
            throw error
        }
        engine = created
        return created
    }

    /// CoreHaptics can resume `@MainActor` work off the main thread; `MainActor.run` may no-op.
    nonisolated private func reclaimMainThread() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
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
    public private(set) var playedImmediatePatterns: [HelmHaptic] = []
    public private(set) var playedAHAPs: [URL] = []
    public private(set) var warmUpCount = 0
    public var supportsHapticsValue = true
    public var isEngineReadyValue = false
    public var builtPatternError: Error?
    public var ahapError: Error?

    public var supportsHaptics: Bool { supportsHapticsValue }
    public var isEngineReady: Bool { isEngineReadyValue }

    public init() {}

    public func playBuiltPatternImmediately(_ pattern: HelmHaptic, lowPowerMode: Bool) -> Bool {
        playedImmediatePatterns.append(pattern)
        return isEngineReadyValue && supportsHapticsValue
    }

    public func warmUp() async throws {
        warmUpCount += 1
        isEngineReadyValue = supportsHapticsValue
    }

    public func playBuiltPattern(_ pattern: HelmHaptic, lowPowerMode: Bool) async throws {
        if let builtPatternError { throw builtPatternError }
        playedPatterns.append(pattern)
        isEngineReadyValue = true
    }

    public func playAHAP(at url: URL, lowPowerMode: Bool) async throws {
        if let ahapError { throw ahapError }
        playedAHAPs.append(url)
    }

    public func invalidate() {}
}

