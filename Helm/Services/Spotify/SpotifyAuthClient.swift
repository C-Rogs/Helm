import AuthenticationServices
import Core
import Foundation
import UIKit

/// Runs Spotify's PKCE authorization code flow and refreshes the resulting session.
@MainActor
final class SpotifyAuthClient: NSObject {
    enum AuthError: LocalizedError, Equatable {
        case cancelled
        case denied(String)
        case badCallback
        case server(Int)
        case malformedResponse
        case transport(String)

        var errorDescription: String? {
            switch self {
            case .cancelled:
                "Spotify sign-in was cancelled."
            case let .denied(reason):
                "Spotify denied the request (\(reason))."
            case .badCallback:
                "Spotify returned an unexpected sign-in response."
            case let .server(status):
                "Spotify rejected the token request (HTTP \(status))."
            case .malformedResponse:
                "Spotify returned a token response Helm could not read."
            case let .transport(message):
                message
            }
        }

        /// A refresh token that Spotify no longer accepts. The account has to be linked again.
        var requiresReauthorization: Bool {
            switch self {
            case let .server(status):
                status == 400 || status == 401
            default:
                false
            }
        }
    }

    private let redirectURI: String
    private let callbackScheme: String
    private let urlSession: URLSession
    private var webSession: ASWebAuthenticationSession?

    init(
        redirectURI: String = SpotifyAppRemoteService.redirectURL.absoluteString,
        callbackScheme: String = SpotifyAppRemoteService.redirectURL.scheme ?? "helm",
        urlSession: URLSession = .shared
    ) {
        self.redirectURI = redirectURI
        self.callbackScheme = callbackScheme
        self.urlSession = urlSession
        super.init()
    }

    func authorize(clientID: String) async throws -> SpotifyAuthSession {
        let verifier = SpotifyPKCE.randomURLSafeString()
        let state = SpotifyPKCE.randomURLSafeString(byteCount: 16)
        guard let url = SpotifyPKCE.authorizationURL(
            clientID: clientID,
            redirectURI: redirectURI,
            codeChallenge: SpotifyPKCE.codeChallenge(verifier: verifier),
            state: state
        ) else {
            throw AuthError.badCallback
        }

        let callback = try await presentWebFlow(url: url)
        let code: String
        switch SpotifyPKCE.authorizationCode(from: callback, expectedState: state) {
        case let .success(value):
            code = value
        case let .failure(error):
            switch error {
            case let .denied(reason):
                throw AuthError.denied(reason)
            default:
                throw AuthError.badCallback
            }
        }

        let body = SpotifyPKCE.tokenExchangeBody(
            clientID: clientID,
            code: code,
            redirectURI: redirectURI,
            codeVerifier: verifier
        )
        return try await requestSession(body: body, existingRefreshToken: nil)
    }

    func refresh(_ session: SpotifyAuthSession, clientID: String) async throws -> SpotifyAuthSession {
        let body = SpotifyPKCE.refreshBody(clientID: clientID, refreshToken: session.refreshToken)
        return try await requestSession(body: body, existingRefreshToken: session.refreshToken)
    }

    private func presentWebFlow(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let callbackURL {
                    continuation.resume(returning: callbackURL)
                    return
                }
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                    return
                }
                continuation.resume(
                    throwing: AuthError.transport(error?.localizedDescription ?? "Spotify sign-in failed.")
                )
            }
            session.presentationContextProvider = self
            // Reuse the Safari login cookie so repeat linking does not require typing credentials.
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            session.start()
        }
    }

    private func requestSession(
        body: String,
        existingRefreshToken: String?
    ) async throws -> SpotifyAuthSession {
        var request = URLRequest(url: SpotifyPKCE.tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(body.utf8)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await urlSession.data(for: request)
        } catch {
            throw AuthError.transport(error.localizedDescription)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AuthError.server(http.statusCode)
        }

        guard let decoded = try? JSONDecoder().decode(SpotifyTokenResponse.self, from: data),
              let session = decoded.session(existingRefreshToken: existingRefreshToken) else {
            throw AuthError.malformedResponse
        }
        return session
    }
}

extension SpotifyAuthClient: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            let window = scenes
                .first { $0.activationState == .foregroundActive }?
                .keyWindow ?? scenes.first?.keyWindow
            return window ?? ASPresentationAnchor()
        }
    }
}
