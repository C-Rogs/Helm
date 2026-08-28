import Foundation
import os

/// Dedicated Gemini `URLSession` so coach traffic does not inherit `URLSession.shared`
/// defaults (60s idle) or unrelated client timeouts.
public enum GeminiHTTPTransport {
    /// Idle gap between packets, including time-to-first-byte on SSE.
    public static let requestIdleTimeout: TimeInterval = 180
    /// Whole-resource cap for a slow stream that is still emitting bytes.
    public static let resourceTimeout: TimeInterval = 600
    /// TLS warmup only; must not block Chat appear.
    public static let prewarmTimeout: TimeInterval = 15
    public static let prewarmCooldown: TimeInterval = 60

    public static let sharedSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = requestIdleTimeout
        config.timeoutIntervalForResource = resourceTimeout
        config.waitsForConnectivity = false
        config.httpMaximumConnectionsPerHost = 2
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: config)
    }()

    private static let lastPrewarmAt = OSAllocatedUnfairLock<Date?>(initialState: nil)

    static func shouldPrewarm(now: Date = Date()) -> Bool {
        lastPrewarmAt.withLock { last in
            if let last, now.timeIntervalSince(last) < prewarmCooldown {
                return false
            }
            last = now
            return true
        }
    }

    static func resetPrewarmCooldownForTests() {
        lastPrewarmAt.withLock { $0 = nil }
    }
}

enum GeminiTransportDiagnostics {
    static func summary(
        elapsed: TimeInterval,
        bodyBytes: Int,
        statusCode: Int? = nil,
        error: Error? = nil
    ) -> String {
        let elapsedMs = Int((elapsed * 1000).rounded())
        let bodyKB = String(format: "%.1f", Double(bodyBytes) / 1024.0)
        var parts = ["elapsed_ms=\(elapsedMs)", "body_kb=\(bodyKB)"]
        if let statusCode {
            parts.append("http=\(statusCode)")
        }
        if let error {
            parts.append(errorCode(for: error))
        }
        return parts.joined(separator: " ")
    }

    static func errorCode(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return "URLError.\(nsError.code)"
        }
        return "\(nsError.domain):\(nsError.code)"
    }
}
