import Foundation
import os

/// Silent OpenRouter key setup for Release builds shared with TestFlight friends.
public enum OpenRouterKeyProvisioner {
    private static let logger = Logger(subsystem: "com.cameronro.helm", category: "CoachLLM")

    public enum ProvisionResult: Sendable, Equatable {
        case skippedDebugBuild
        case alreadyPresent
        case notConfigured
        case provisioned(wasNew: Bool)
        case failed(String)
    }

    public static func provisionIfNeeded(
        keyStore: APIKeyStore = APIKeyStore(),
        client: CoachKeyServiceClient = CoachKeyServiceClient()
    ) async -> ProvisionResult {
        #if DEBUG
        return .skippedDebugBuild
        #else
        guard !keyStore.hasKey(kind: .openRouter) else {
            return .alreadyPresent
        }

        guard CoachKeyServiceConfig.isConfigured else {
            logger.warning("openrouter provision skipped: key service URL not configured")
            return .notConfigured
        }

        do {
            let deviceId = try HelmDeviceIdentity.deviceId()
            let response = try await client.provision(deviceId: deviceId)
            try keyStore.save(response.key, kind: .openRouter)
            logger.info("openrouter key provisioned (new=\(response.provisioned, privacy: .public))")
            return .provisioned(wasNew: response.provisioned)
        } catch {
            logger.error("openrouter provision failed: \(error.localizedDescription, privacy: .public)")
            if let serviceError = error as? CoachKeyServiceError {
                return .failed(serviceError.localizedDescription)
            }
            return .failed(error.localizedDescription)
        }
        #endif
    }
}

extension CoachKeyServiceError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .notConfigured:
            "Helm cloud key service is not configured yet."
        case .invalidResponse:
            "Unexpected response from Helm key service."
        case .unauthorized:
            "Helm key service rejected this app build."
        case .deviceCapReached:
            "Helm tester device limit reached. Contact Cameron to raise the cap."
        case .serverError(let message):
            message
        }
    }
}
