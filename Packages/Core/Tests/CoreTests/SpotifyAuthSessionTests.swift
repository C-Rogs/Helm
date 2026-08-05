import Foundation
import Testing

@testable import Core

@Suite("Spotify auth session")
struct SpotifyAuthSessionTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Token well inside its lifetime needs no refresh")
    func freshTokenDoesNotNeedRefresh() {
        let session = SpotifyAuthSession(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: now.addingTimeInterval(3600)
        )
        #expect(session.needsRefresh(now: now) == false)
    }

    @Test("Token inside the leeway window refreshes early")
    func nearExpiryNeedsRefresh() {
        let session = SpotifyAuthSession(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: now.addingTimeInterval(SpotifyAuthSession.refreshLeeway - 1)
        )
        #expect(session.needsRefresh(now: now))
    }

    @Test("Expired token needs refresh")
    func expiredNeedsRefresh() {
        let session = SpotifyAuthSession(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: now.addingTimeInterval(-1)
        )
        #expect(session.needsRefresh(now: now))
    }

    @Test("Session survives a round trip through JSON")
    func codableRoundTrip() throws {
        let session = SpotifyAuthSession(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: now
        )
        let data = try JSONEncoder().encode(session)
        #expect(try JSONDecoder().decode(SpotifyAuthSession.self, from: data) == session)
    }
}

@Suite("Spotify token response")
struct SpotifyTokenResponseTests {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Refresh response without a new refresh token keeps the existing one")
    func keepsExistingRefreshToken() {
        let response = SpotifyTokenResponse(accessToken: "new", refreshToken: nil, expiresIn: 3600)
        let session = response.session(existingRefreshToken: "old", now: now)
        #expect(session?.accessToken == "new")
        #expect(session?.refreshToken == "old")
        #expect(session?.expiresAt == now.addingTimeInterval(3600))
    }

    @Test("Rotated refresh token replaces the stored one")
    func rotatedRefreshTokenWins() {
        let response = SpotifyTokenResponse(accessToken: "new", refreshToken: "rotated", expiresIn: 60)
        #expect(response.session(existingRefreshToken: "old", now: now)?.refreshToken == "rotated")
    }

    @Test("No refresh token at all yields no session")
    func missingRefreshTokenFails() {
        let response = SpotifyTokenResponse(accessToken: "new", refreshToken: nil, expiresIn: 60)
        #expect(response.session(existingRefreshToken: nil, now: now) == nil)
    }

    @Test("Decodes Spotify's snake_case payload")
    func decodesPayload() throws {
        let json = Data(#"{"access_token":"a","refresh_token":"r","expires_in":3600}"#.utf8)
        let decoded = try JSONDecoder().decode(SpotifyTokenResponse.self, from: json)
        #expect(decoded == SpotifyTokenResponse(accessToken: "a", refreshToken: "r", expiresIn: 3600))
    }
}

@Suite("Spotify PKCE")
struct SpotifyPKCETests {
    @Test("Code challenge matches the RFC 7636 test vector")
    func codeChallengeVector() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(SpotifyPKCE.codeChallenge(verifier: verifier) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("Verifier is URL safe and within the allowed length")
    func verifierIsURLSafe() {
        let verifier = SpotifyPKCE.randomURLSafeString()
        #expect(verifier.count >= 43 && verifier.count <= 128)
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        #expect(verifier.unicodeScalars.allSatisfy { allowed.contains($0) })
    }

    @Test("Authorization URL carries the PKCE parameters and app-remote scope")
    func authorizationURLParameters() throws {
        let url = try #require(SpotifyPKCE.authorizationURL(
            clientID: "client",
            redirectURI: "helm://spotify-callback",
            codeChallenge: "challenge",
            state: "state"
        ))
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        #expect(url.host == "accounts.spotify.com")
        #expect(value("client_id") == "client")
        #expect(value("response_type") == "code")
        #expect(value("code_challenge_method") == "S256")
        #expect(value("code_challenge") == "challenge")
        #expect(value("state") == "state")
        #expect(value("redirect_uri") == "helm://spotify-callback")
        #expect(value("scope")?.contains("app-remote-control") == true)
    }

    @Test("Token exchange body is form encoded with the verifier")
    func tokenExchangeBody() {
        let body = SpotifyPKCE.tokenExchangeBody(
            clientID: "client",
            code: "code",
            redirectURI: "helm://spotify-callback",
            codeVerifier: "verifier"
        )
        #expect(body.contains("grant_type=authorization_code"))
        #expect(body.contains("code_verifier=verifier"))
        #expect(body.contains("redirect_uri=helm%3A%2F%2Fspotify-callback"))
    }

    @Test("Refresh body uses the refresh grant")
    func refreshBody() {
        let body = SpotifyPKCE.refreshBody(clientID: "client", refreshToken: "r/t")
        #expect(body.contains("grant_type=refresh_token"))
        #expect(body.contains("refresh_token=r%2Ft"))
        #expect(body.contains("client_id=client"))
    }

    @Test("Callback with matching state yields the code")
    func callbackSuccess() throws {
        let url = try #require(URL(string: "helm://spotify-callback?code=abc&state=xyz"))
        #expect(SpotifyPKCE.authorizationCode(from: url, expectedState: "xyz") == .success("abc"))
    }

    @Test("Mismatched state is rejected")
    func callbackStateMismatch() throws {
        let url = try #require(URL(string: "helm://spotify-callback?code=abc&state=other"))
        #expect(SpotifyPKCE.authorizationCode(from: url, expectedState: "xyz") == .failure(.stateMismatch))
    }

    @Test("User denial is reported as denied")
    func callbackDenied() throws {
        let url = try #require(URL(string: "helm://spotify-callback?error=access_denied&state=xyz"))
        #expect(SpotifyPKCE.authorizationCode(from: url, expectedState: "xyz") == .failure(.denied("access_denied")))
    }

    @Test("Callback without a code is rejected")
    func callbackMissingCode() throws {
        let url = try #require(URL(string: "helm://spotify-callback?state=xyz"))
        #expect(SpotifyPKCE.authorizationCode(from: url, expectedState: "xyz") == .failure(.missingCode))
    }
}
