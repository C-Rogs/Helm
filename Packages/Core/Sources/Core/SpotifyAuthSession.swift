import CryptoKit
import Foundation

/// Persisted Spotify OAuth session obtained via the PKCE authorization code flow.
///
/// The App Remote SDK's own token renewal requires a backend token swap service, so Helm runs
/// the PKCE flow directly and keeps the refresh token. Access tokens live ~1 hour; the refresh
/// token keeps the account linked across launches until the user revokes it.
public struct SpotifyAuthSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    /// Renew before the token actually dies so a workout never starts on a token about to expire.
    public static let refreshLeeway: TimeInterval = 300

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }

    public func needsRefresh(now: Date = Date()) -> Bool {
        expiresAt.timeIntervalSince(now) <= Self.refreshLeeway
    }
}

/// Token endpoint payload for both the initial code exchange and subsequent refreshes.
public struct SpotifyTokenResponse: Decodable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Double

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
    }

    public init(accessToken: String, refreshToken: String?, expiresIn: Double) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresIn = expiresIn
    }

    /// Refresh responses may omit `refresh_token`, in which case the existing one stays valid.
    public func session(existingRefreshToken: String?, now: Date = Date()) -> SpotifyAuthSession? {
        guard let refreshToken = refreshToken ?? existingRefreshToken, !refreshToken.isEmpty else {
            return nil
        }
        guard !accessToken.isEmpty else { return nil }
        return SpotifyAuthSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(expiresIn)
        )
    }
}

public enum SpotifyAuthCallbackError: Error, Equatable, Sendable {
    case notACallback
    case stateMismatch
    case denied(String)
    case missingCode
}

/// URL and body construction for Spotify's PKCE authorization code flow.
public enum SpotifyPKCE {
    public static let authorizeEndpoint = URL(string: "https://accounts.spotify.com/authorize")!
    public static let tokenEndpoint = URL(string: "https://accounts.spotify.com/api/token")!

    /// `app-remote-control` is what App Remote needs; the playback scopes let us read now playing.
    public static let scopes = [
        "app-remote-control",
        "user-read-playback-state",
        "user-read-currently-playing"
    ]

    public static func randomURLSafeString(byteCount: Int = 64) -> String {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        for index in bytes.indices {
            bytes[index] = UInt8.random(in: UInt8.min...UInt8.max)
        }
        return base64URLEncoded(Data(bytes))
    }

    public static func codeChallenge(verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncoded(Data(digest))
    }

    public static func authorizationURL(
        clientID: String,
        redirectURI: String,
        codeChallenge: String,
        state: String
    ) -> URL? {
        var components = URLComponents(url: authorizeEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " "))
        ]
        return components?.url
    }

    public static func tokenExchangeBody(
        clientID: String,
        code: String,
        redirectURI: String,
        codeVerifier: String
    ) -> String {
        formEncoded([
            ("grant_type", "authorization_code"),
            ("code", code),
            ("redirect_uri", redirectURI),
            ("client_id", clientID),
            ("code_verifier", codeVerifier)
        ])
    }

    public static func refreshBody(clientID: String, refreshToken: String) -> String {
        formEncoded([
            ("grant_type", "refresh_token"),
            ("refresh_token", refreshToken),
            ("client_id", clientID)
        ])
    }

    public static func authorizationCode(
        from url: URL,
        expectedState: String
    ) -> Result<String, SpotifyAuthCallbackError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .failure(.notACallback)
        }
        let items = components.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name == name }?.value
        }

        guard value("state") == expectedState else { return .failure(.stateMismatch) }
        if let error = value("error"), !error.isEmpty {
            return .failure(.denied(error))
        }
        guard let code = value("code"), !code.isEmpty else { return .failure(.missingCode) }
        return .success(code)
    }

    private static func formEncoded(_ pairs: [(String, String)]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return pairs
            .map { key, value in
                let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? key
                let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")
    }

    private static func base64URLEncoded(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
