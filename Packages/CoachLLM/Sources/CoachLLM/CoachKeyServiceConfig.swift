import Foundation

/// Personal Coacher Cloudflare Worker that mints capped, free-model-only OpenRouter keys.
///
/// **Friends-only caveat:** `appSharedSecret` ships in the Release binary. Anyone who extracts it
/// can call `/v1/provision` until you rotate `APP_SHARED_SECRET` on the worker. Fine for a capped
/// TestFlight circle; do not ship this configuration to the public App Store.
public enum CoachKeyServiceConfig: Sendable {
    /// Deployed worker URL, e.g. `https://coach-key-service.your-subdomain.workers.dev`
    public static let baseURLString = "https://coach-key-service.REPLACE_ME.workers.dev"

    /// Must match worker secret `APP_SHARED_SECRET` (`openssl rand -hex 32`).
    public static let appSharedSecret = "REPLACE_WITH_OPENSSL_RAND_HEX_32"

    public static var baseURL: URL? {
        URL(string: baseURLString)
    }

    public static var isConfigured: Bool {
        guard let baseURL else { return false }
        return !baseURL.absoluteString.contains("REPLACE_ME")
            && appSharedSecret != "REPLACE_WITH_OPENSSL_RAND_HEX_32"
    }
}
