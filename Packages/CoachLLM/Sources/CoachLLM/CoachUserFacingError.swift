import Foundation

public enum CoachUserFacingError: Sendable {
    public static func message(for error: Error) -> String {
        if let structured = error as? CoachStructuredOutputError {
            return message(for: structured)
        }
        if let provider = error as? CoachProviderError {
            return message(for: provider)
        }
        let localized = (error as? LocalizedError)?.errorDescription
        if let localized, !localized.isEmpty {
            return localized
        }
        return CoachFailurePolicy.degradedState(for: error).userMessage
    }

    public static func message(for error: CoachStructuredOutputError) -> String {
        switch error {
        case .schemaVersionMismatch:
            return "Coach returned an outdated response format. Try again."
        case .decodingFailed:
            return "Coach returned an invalid adjustment. Try rephrasing."
        case .emptyResponse:
            return "Coach returned an empty response. Try again."
        }
    }

    public static func message(for error: CoachProviderError) -> String {
        switch error {
        case .rateLimited:
            return "Coach is cooling down. Try again shortly."
        case .timeout:
            return "Coach timed out. Check your connection and try again."
        case .offline:
            return "Coach is offline. Numbers and logging still work."
        case .unavailable(let message):
            return message
        case .contextTooLarge:
            return "Context is too large for this provider. Trim history or import fewer days."
        case .cancelled:
            return "Coach response cancelled."
        case .requestFailed(let detail):
            return "Coach request failed (\(detail))."
        }
    }
}

extension CoachStructuredOutputError: LocalizedError {
    public var errorDescription: String? {
        CoachUserFacingError.message(for: self)
    }
}

extension CoachProviderError: LocalizedError {
    public var errorDescription: String? {
        CoachUserFacingError.message(for: self)
    }
}
