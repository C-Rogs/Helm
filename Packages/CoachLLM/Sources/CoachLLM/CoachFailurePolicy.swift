import Foundation

public enum CoachProviderError: Error, Sendable, Equatable {
    case rateLimited
    case timeout
    case offline
    case unavailable(String)
    case contextTooLarge
    case cancelled
    case requestFailed(String)

    public static func fromHTTPStatusCode(_ statusCode: Int) -> CoachProviderError {
        switch statusCode {
        case 429:
            .rateLimited
        case 408, 504:
            .timeout
        default:
            .requestFailed("HTTP \(statusCode)")
        }
    }
}

public enum CoachDegradedMode: String, Sendable, Equatable {
    case engineOnly
}

public enum CoachDegradedReason: String, Sendable, Equatable {
    case rateLimited
    case timeout
    case offline
    case providerUnavailable
    case cancelled
    case contextTooLarge
    case other
}

public struct CoachDegradedState: Sendable, Equatable {
    public let mode: CoachDegradedMode
    public let reason: CoachDegradedReason
    public let userMessage: String

    public init(mode: CoachDegradedMode, reason: CoachDegradedReason, userMessage: String) {
        self.mode = mode
        self.reason = reason
        self.userMessage = userMessage
    }

    public static let offline = CoachDegradedState(
        mode: .engineOnly,
        reason: .offline,
        userMessage: "Coach is offline. Numbers and logging still work."
    )
}

/// Maps provider errors to the engine-only fallback the UI renders when the coach is unavailable.
public enum CoachFailurePolicy: Sendable {
    public static func degradedState(for error: Error) -> CoachDegradedState {
        if let structuredError = error as? CoachStructuredOutputError {
            return CoachDegradedState(
                mode: .engineOnly,
                reason: .other,
                userMessage: CoachUserFacingError.message(for: structuredError)
            )
        }

        if let providerError = error as? CoachProviderError {
            return degradedState(for: providerError)
        }

        if let urlError = error as? URLError {
            return degradedState(for: urlError)
        }

        if let decodingError = error as? DecodingError {
            return CoachDegradedState(
                mode: .engineOnly,
                reason: .other,
                userMessage: decodingHint(for: decodingError)
            )
        }

        if error is CancellationError {
            return CoachDegradedState(
                mode: .engineOnly,
                reason: .cancelled,
                userMessage: "Coach response cancelled."
            )
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain, nsError.code == 4865 {
            return CoachDegradedState(
                mode: .engineOnly,
                reason: .other,
                userMessage: "Coach memory data needs a refresh. Open Settings → Coach → Coach Memory, save once, then try again."
            )
        }
        if nsError.domain == NSURLErrorDomain {
            return degradedState(for: URLError(_nsError: nsError))
        }

        if let localized = (error as? LocalizedError)?.errorDescription, !localized.isEmpty {
            return CoachDegradedState(
                mode: .engineOnly,
                reason: .other,
                userMessage: localized
            )
        }

        return CoachDegradedState(
            mode: .engineOnly,
            reason: .other,
            userMessage: "Coach request failed. Numbers and logging still work."
        )
    }

    // MARK: - Helpers

    private static func decodingHint(for error: DecodingError) -> String {
        switch error {
        case .keyNotFound(_, _):
            return "Coach memory data needs a refresh. Open Settings → Coach → Coach Memory, save once, then try again."
        case .dataCorrupted:
            return "Coach data is corrupted. Open Settings → Coach → Coach Memory, save once, then try again."
        default:
            return "Coach couldn't parse a response. Try again."
        }
    }

    public static func degradedState(for error: CoachProviderError) -> CoachDegradedState {
        switch error {
        case .rateLimited:
            CoachDegradedState(
                mode: .engineOnly,
                reason: .rateLimited,
                userMessage: "Coach is cooling down. Numbers and logging still work."
            )
        case .timeout:
            CoachDegradedState(
                mode: .engineOnly,
                reason: .timeout,
                userMessage: "Coach timed out. Numbers and logging still work."
            )
        case .offline:
            .offline
        case .unavailable(let message):
            CoachDegradedState(
                mode: .engineOnly,
                reason: .providerUnavailable,
                userMessage: message
            )
        case .contextTooLarge:
            CoachDegradedState(
                mode: .engineOnly,
                reason: .contextTooLarge,
                userMessage: "Context is too large for this provider. Trim history or import fewer days."
            )
        case .cancelled:
            CoachDegradedState(
                mode: .engineOnly,
                reason: .cancelled,
                userMessage: "Coach response cancelled."
            )
        case .requestFailed:
            CoachDegradedState(
                mode: .engineOnly,
                reason: .other,
                userMessage: CoachUserFacingError.message(for: error)
            )
        }
    }

    public static func degradedState(for error: URLError) -> CoachDegradedState {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed, .internationalRoamingOff:
            return .offline
        case .timedOut:
            return CoachDegradedState(
                mode: .engineOnly,
                reason: .timeout,
                userMessage: "Coach timed out. Numbers and logging still work."
            )
        case .cannotConnectToHost, .dnsLookupFailed, .cannotFindHost:
            return CoachDegradedState(
                mode: .engineOnly,
                reason: .timeout,
                userMessage: "Coach couldn't reach Gemini. Check your connection and try again."
            )
        case .secureConnectionFailed, .serverCertificateUntrusted,
             .clientCertificateRejected, .clientCertificateRequired:
            return CoachDegradedState(
                mode: .engineOnly,
                reason: .other,
                userMessage: "Coach couldn't reach Gemini securely. Try again."
            )
        case .cancelled:
            return CoachDegradedState(
                mode: .engineOnly,
                reason: .cancelled,
                userMessage: "Coach response cancelled."
            )
        default:
            let detail = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = detail.isEmpty
                ? "Coach request failed. Numbers and logging still work."
                : "Coach request failed (\(detail)). Numbers and logging still work."
            return CoachDegradedState(
                mode: .engineOnly,
                reason: .other,
                userMessage: message
            )
        }
    }
}
