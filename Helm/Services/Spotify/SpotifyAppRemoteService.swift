import CoachLLM
import Core
import Diagnostics
import Foundation
import SpotifyiOS

/// Connects to Spotify App Remote for now-playing metadata during workouts.
@MainActor
final class SpotifyAppRemoteService: NSObject, ObservableObject {
    static let shared = SpotifyAppRemoteService()

    static let redirectURL = URL(string: "helm://spotify-callback")!

    @Published private(set) var isAuthorized = false
    @Published private(set) var isConnected = false
    @Published private(set) var isAuthorizing = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isConnecting = false

    var isReconnecting: Bool { isConnecting || disconnectingForLifecycle }

    var workoutMusicChipTitle: String {
        if isConnected { return "Spotify connected" }
        if isReconnecting { return "Reconnecting Spotify" }
        return "Tap to wake Spotify"
    }

    /// App Remote only connects while the Spotify app is running and playing, so a workout that
    /// starts before the music does keeps retrying rather than silently capturing nothing.
    private static let maxConnectAttempts = 4
    private static let connectRetryDelays: [Duration] = [.seconds(5), .seconds(15), .seconds(45)]

    static let spotifyIdleMessage = "Open Spotify and start playing. Signal connects once music is running."

    private let authClient: SpotifyAuthClient
    private let logger = helmLogger(category: .ui)
    private var appRemote: SPTAppRemote?
    private var session: SpotifyAuthSession?
    private var onTrackChange: ((NowPlayingSnapshot) -> Void)?
    private var lastTrackKey: String?
    private var workoutCaptureActive = false
    private var connectAttempts = 0
    private var didRetryAfterAuthFailure = false
    /// True while we tear down App Remote for scene resign; skip error UI and reconnect until become-active.
    private var disconnectingForLifecycle = false
    /// Short-lived token handed back by the Spotify app switch. Preferred for App Remote when we
    /// have one, because App Remote may reject a token minted by the web flow.
    private var appRemoteToken: String?
    private var refreshTask: Task<SpotifyAuthSession?, Never>?

    private init(authClient: SpotifyAuthClient? = nil) {
        self.authClient = authClient ?? SpotifyAuthClient()
        super.init()
    }

    var hasClientID: Bool {
        guard let clientID else { return false }
        return !clientID.isEmpty
    }

    func configure() {
        session = SpotifySessionStore.load()
        isAuthorized = session != nil
        guard let clientID, let session else { return }
        remote(clientID: clientID).connectionParameters.accessToken = session.accessToken
    }

    func authorize() {
        guard !isAuthorizing else { return }
        lastErrorMessage = nil
        guard let clientID, !clientID.isEmpty else {
            lastErrorMessage = "Add spotify-client-id.key under Secrets/ and rebuild Debug."
            return
        }

        isAuthorizing = true
        Task {
            defer { isAuthorizing = false }
            do {
                let newSession = try await authClient.authorize(clientID: clientID)
                store(newSession)
                // Deliberately no connect() here: App Remote needs Spotify playing, which it is
                // not right after a web sign-in. The link happens when a workout starts.
                remote(clientID: clientID).connectionParameters.accessToken = newSession.accessToken
            } catch {
                lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                logger.error("Spotify authorization failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func connectForWorkout(onTrackChange: @escaping (NowPlayingSnapshot) -> Void) {
        self.onTrackChange = onTrackChange
        lastTrackKey = nil
        workoutCaptureActive = true
        connectAttempts = 0
        didRetryAfterAuthFailure = false
        guard isAuthorized else { return }
        Task { await connectUsingFreshToken() }
    }

    /// Spotify lifecycle: disconnect App Remote when Helm resigns active. Keeps the account link
    /// and workout capture intent so become-active can silently reconnect.
    func handleAppResignActive() {
        guard appRemote?.isConnected == true || isConnected else { return }
        disconnectingForLifecycle = true
        appRemote?.playerAPI?.unsubscribe(toPlayerState: { _, _ in })
        appRemote?.disconnect()
        isConnected = false
    }

    /// Spotify lifecycle: silent `connect()` when returning to foreground with a token.
    func handleAppBecomeActive() {
        disconnectingForLifecycle = false
        guard isAuthorized, workoutCaptureActive else { return }
        guard appRemoteToken != nil || session != nil else { return }
        Task { await connectUsingFreshToken() }
    }

    /// One-shot connect used by Settings so the link can be checked without starting a workout.
    func verifyConnection() {
        guard isAuthorized else { return }
        lastErrorMessage = nil
        connectAttempts = 0
        didRetryAfterAuthFailure = false
        Task { await connectUsingFreshToken() }
    }

    /// Explicit user action ("Open Spotify"). App-switches to wake Spotify, resumes the last track,
    /// and returns a token via `handleRedirect`. Never call this automatically on workout start.
    func wakeSpotifyAndConnect() {
        guard isAuthorized, let clientID, !clientID.isEmpty else { return }
        lastErrorMessage = nil
        connectAttempts = 0
        didRetryAfterAuthFailure = false

        remote(clientID: clientID).authorizeAndPlayURI("") { [weak self] spotifyInstalled in
            Task { @MainActor in
                guard let self else { return }
                guard spotifyInstalled else {
                    self.lastErrorMessage = "Install Spotify from the App Store, then try again."
                    return
                }
                // Spotify needs a beat to come up and start playback before it accepts a
                // connection. If the redirect beats us here it has already connected.
                try? await Task.sleep(for: .seconds(2))
                guard !self.isConnected else { return }
                await self.connectUsingFreshToken()
            }
        }
    }

    /// Handles the `helm://spotify-callback` redirect from the Spotify app switch. The web sign-in
    /// uses `ASWebAuthenticationSession`, which consumes its own callback, so anything arriving
    /// here came from `authorizeAndPlayURI`.
    @discardableResult
    func handleRedirect(_ url: URL) -> Bool {
        guard Self.isRedirectURL(url) else { return false }
        guard let clientID, !clientID.isEmpty else { return true }

        let remote = remote(clientID: clientID)
        guard let parameters = remote.authorizationParameters(from: url) else { return true }

        if let token = parameters[SPTAppRemoteAccessTokenKey], !token.isEmpty {
            appRemoteToken = token
            remote.connectionParameters.accessToken = token
            lastErrorMessage = nil
            connectAttempts += 1
            remote.connect()
        } else if let description = parameters[SPTAppRemoteErrorDescriptionKey] {
            lastErrorMessage = description
        }
        return true
    }

    static func isRedirectURL(_ url: URL) -> Bool {
        url.scheme?.lowercased() == redirectURL.scheme
            && url.host?.lowercased() == redirectURL.host
    }

    func disconnectWorkoutSession() {
        workoutCaptureActive = false
        disconnectingForLifecycle = false
        onTrackChange = nil
        lastTrackKey = nil
        appRemote?.playerAPI?.unsubscribe(toPlayerState: { _, _ in })
        appRemote?.disconnect()
        isConnected = false
    }

    func disconnectAccount() {
        disconnectWorkoutSession()
        refreshTask?.cancel()
        refreshTask = nil
        SpotifySessionStore.clear()
        session = nil
        appRemoteToken = nil
        appRemote?.connectionParameters.accessToken = nil
        isAuthorized = false
        lastErrorMessage = nil
    }

    private var clientID: String? {
        try? APIKeyStore().load(kind: .spotifyClientID)
    }

    private func remote(clientID: String) -> SPTAppRemote {
        // Reuse the instance that started a connection; recreating it would drop a live App Remote link.
        if let appRemote { return appRemote }
        let configuration = SPTConfiguration(clientID: clientID, redirectURL: Self.redirectURL)
        // Spotify requires a playURI so authorization also wakes the app for App Remote.
        configuration.playURI = ""
        let created = SPTAppRemote(configuration: configuration, logLevel: .none)
        created.delegate = self
        appRemote = created
        return created
    }

    private func store(_ session: SpotifyAuthSession) {
        self.session = session
        let status = SpotifySessionStore.save(session)
        if status == errSecSuccess {
            isAuthorized = true
            lastErrorMessage = nil
        } else {
            // Without a persisted session the link silently dies at next launch, so say so now.
            isAuthorized = true
            lastErrorMessage = "Spotify is linked for now, but Signal could not save it (Keychain error \(status))."
            logger.error("Spotify Keychain write failed with status \(status, privacy: .public)")
        }
    }

    private func connectUsingFreshToken() async {
        guard let clientID, !clientID.isEmpty else { return }
        let remote = remote(clientID: clientID)

        if let appRemoteToken {
            remote.connectionParameters.accessToken = appRemoteToken
        } else {
            guard let session = await freshSession(clientID: clientID) else { return }
            remote.connectionParameters.accessToken = session.accessToken
        }

        guard !remote.isConnected else { return }
        isConnecting = true
        connectAttempts += 1
        remote.connect()
    }

    /// Returns a session whose access token is valid, refreshing it when it is close to expiry.
    private func freshSession(clientID: String) async -> SpotifyAuthSession? {
        guard let current = session else { return nil }
        guard current.needsRefresh() else { return current }

        if let refreshTask {
            return await refreshTask.value
        }

        let task = Task<SpotifyAuthSession?, Never> { [authClient] in
            do {
                return try await authClient.refresh(current, clientID: clientID)
            } catch {
                await self.handleRefreshFailure(error)
                return nil
            }
        }
        refreshTask = task
        let refreshed = await task.value
        refreshTask = nil

        guard let refreshed else { return nil }
        store(refreshed)
        return refreshed
    }

    private func handleRefreshFailure(_ error: Error) {
        logger.error("Spotify token refresh failed: \(String(describing: error), privacy: .public)")
        if let authError = error as? SpotifyAuthClient.AuthError, authError.requiresReauthorization {
            SpotifySessionStore.clear()
            session = nil
            isAuthorized = false
            lastErrorMessage = "Spotify sign-in expired. Reconnect Spotify in Settings."
            return
        }
        lastErrorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    func nudgeReconnectIfCapturing() {
        guard workoutCaptureActive, isAuthorized, !isConnected else { return }
        Task { await connectUsingFreshToken() }
    }

    private func scheduleReconnect() {
        guard workoutCaptureActive, isAuthorized else { return }
        guard connectAttempts < Self.maxConnectAttempts else { return }
        let delay = Self.connectRetryDelays[min(connectAttempts - 1, Self.connectRetryDelays.count - 1)]
        Task {
            try? await Task.sleep(for: delay)
            guard workoutCaptureActive, !isConnected else { return }
            await connectUsingFreshToken()
        }
    }

    private func handleConnectionFailure(_ error: Error?) {
        isConnected = false
        isConnecting = false
        if let error {
            logger.error("Spotify App Remote connect failed: \(String(describing: error), privacy: .public)")
        }

        lastErrorMessage = Self.connectionFailureMessage(error)

        // A rejected token can survive our expiry check (revoked, scope change), so force one refresh.
        if !didRetryAfterAuthFailure, appRemoteToken == nil, let session {
            didRetryAfterAuthFailure = true
            self.session = SpotifyAuthSession(
                accessToken: session.accessToken,
                refreshToken: session.refreshToken,
                expiresAt: .distantPast
            )
        }

        scheduleReconnect()
    }

    /// The SDK reports "Connection attempt failed." for the common case of Spotify being asleep,
    /// which reads like a Helm bug. Keep the underlying domain and code visible so a failure that
    /// is not the sleeping-Spotify case can still be identified from the screen.
    private static func connectionFailureMessage(_ error: Error?) -> String {
        guard let error else { return spotifyIdleMessage }
        let nsError = error as NSError
        var detail = "\(nsError.domain) \(nsError.code)"
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            detail += " / \(underlying.domain) \(underlying.code)"
        }
        guard nsError.domain.hasPrefix("com.spotify.app-remote") else {
            return "\(error.localizedDescription) [\(detail)]"
        }
        return "\(spotifyIdleMessage)\n\(error.localizedDescription) [\(detail)]"
    }

    private func publishTrackChange(title: String?, artist: String?, album: String?, spotifyURI: String?) {
        guard let snapshot = SpotifyPlayerStateMapping.nowPlayingSnapshot(
            title: title,
            artist: artist,
            album: album,
            spotifyURI: spotifyURI
        ) else {
            return
        }

        let key = "\(snapshot.title ?? "")|\(snapshot.artist ?? "")"
        guard key != lastTrackKey else { return }
        lastTrackKey = key
        onTrackChange?(snapshot)
    }
}

extension SpotifyAppRemoteService: SPTAppRemoteDelegate {
    nonisolated func appRemoteDidEstablishConnection(_ appRemote: SPTAppRemote) {
        Task { @MainActor in
            guard let appRemote = self.appRemote else { return }
            self.isConnected = true
            self.isConnecting = false
            self.connectAttempts = 0
            self.didRetryAfterAuthFailure = false
            self.lastErrorMessage = nil
            appRemote.playerAPI?.delegate = self
            appRemote.playerAPI?.subscribe(toPlayerState: { [weak self] _, error in
                if let error {
                    Task { @MainActor in
                        self?.lastErrorMessage = error.localizedDescription
                    }
                }
            })
            appRemote.playerAPI?.getPlayerState { [weak self] result, _ in
                guard let state = result as? SPTAppRemotePlayerState else { return }
                let title = state.track.name
                let artist = state.track.artist.name
                let album = state.track.album.name
                let spotifyURI = state.track.uri
                Task { @MainActor in
                    self?.publishTrackChange(title: title, artist: artist, album: album, spotifyURI: spotifyURI)
                }
            }
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didFailConnectionAttemptWithError error: Error?) {
        Task { @MainActor in
            self.handleConnectionFailure(error)
        }
    }

    nonisolated func appRemote(_ appRemote: SPTAppRemote, didDisconnectWithError error: Error?) {
        Task { @MainActor in
            self.isConnected = false
            if self.disconnectingForLifecycle {
                self.disconnectingForLifecycle = false
                return
            }
            if let error {
                self.lastErrorMessage = error.localizedDescription
            }
            self.scheduleReconnect()
        }
    }
}

extension SpotifyAppRemoteService: SPTAppRemotePlayerStateDelegate {
    nonisolated func playerStateDidChange(_ playerState: SPTAppRemotePlayerState) {
        let title = playerState.track.name
        let artist = playerState.track.artist.name
        let album = playerState.track.album.name
        let spotifyURI = playerState.track.uri
        Task { @MainActor in
            self.publishTrackChange(title: title, artist: artist, album: album, spotifyURI: spotifyURI)
        }
    }
}
