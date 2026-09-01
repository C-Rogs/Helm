import DesignSystem
import SwiftUI

struct SpotifySettingsView: View {
    @ObservedObject private var spotify = SpotifyAppRemoteService.shared
    @Bindable private var tempoPreferences = SongTempoPreferences.shared
    private let tempoCache = SongTempoCache.shared

    var body: some View {
        List {
            Section {
                Text("Signal reads now playing from Spotify during workouts and shows tracks on the session timeline.")
                    .helmType(.body, color: HelmColor.fgSecondary)
                    .helmListRowChrome()
            }

            Section("Status") {
                HelmStatusRow(
                    label: "Account",
                    value: spotify.isAuthorized ? "Linked" : "Not linked",
                    valueColor: spotify.isAuthorized ? HelmColor.ready : HelmColor.fgMuted
                )
                .helmListRowChrome()

                if spotify.isAuthorized {
                    HelmStatusRow(
                        label: "App Remote",
                        value: spotify.isConnected ? "Live" : "Idle",
                        valueColor: spotify.isConnected ? HelmColor.ready : HelmColor.fgMuted
                    )
                    .helmListRowChrome()

                    Button("Open Spotify") {
                        spotify.wakeSpotifyAndConnect()
                    }
                    .helmListRowChrome()

                    Button("Test connection") {
                        spotify.verifyConnection()
                    }
                    .helmListRowChrome()
                }

                if let lastErrorMessage = spotify.lastErrorMessage {
                    Label(lastErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .helmType(.body, color: HelmColor.compromised)
                        .helmListRowChrome()
                }
            }

            Section("Song tempo") {
                Toggle("Look up song tempo", isOn: $tempoPreferences.lookupEnabled)
                    .helmListRowChrome()

                Text(
                    """
                    Spotify stopped serving tempo to apps in 2024 and Apple Music never did. \
                    With this on, Helm fills in missing tempos: \
                    Helm first asks ReccoBeats using Spotify's track ID, then falls back to \
                    Deezer by title and artist. Coverage is partial; tracks \
                    without a tempo still show as spans on the timeline.
                    """
                )
                .helmType(.body, color: HelmColor.fgMuted)
                .helmListRowChrome()

                HelmStatusRow(
                    label: "Tempos cached",
                    value: "\(tempoCache.knownTempoCount)",
                    valueColor: HelmColor.fgSecondary
                )
                .helmListRowChrome()

                if tempoCache.knownTempoCount > 0 {
                    Button("Clear cached tempos", role: .destructive) {
                        tempoCache.clear()
                    }
                    .helmListRowChrome()
                }
            }

            Section {
                if spotify.isAuthorized {
                    Button("Disconnect Spotify", role: .destructive) {
                        spotify.disconnectAccount()
                    }
                    .helmListRowChrome()
                } else {
                    Button(spotify.isAuthorizing ? "Connecting…" : "Connect Spotify") {
                        spotify.authorize()
                    }
                    .disabled(!spotify.hasClientID || spotify.isAuthorizing)
                    .helmListRowChrome()
                }
            }

            if !spotify.hasClientID {
                Section("Setup") {
                    Text("Add a Spotify Developer client ID at Secrets/spotify-client-id.key to enable linking.")
                        .helmType(.body, color: HelmColor.fgMuted)
                        .helmListRowChrome()
                    Text("Spotify Dashboard redirect URI: helm://spotify-callback")
                        .helmType(.monoTag, color: HelmColor.fgMuted)
                        .helmListRowChrome()
                }
            } else {
                Section {
                    Text(
                        """
                        Linking is one time. Signal connects silently when Spotify is already \
                        playing. Open Spotify (here or during a workout) only when you want \
                        Signal to wake the Spotify app; that switch is intentional.
                        """
                    )
                    .helmType(.body, color: HelmColor.fgMuted)
                    .helmListRowChrome()
                }
            }
        }
        .helmSettingsListChrome()
        .navigationTitle("Spotify")
        .onAppear {
            spotify.configure()
        }
    }
}

#Preview("Spotify settings") {
    NavigationStack {
        SpotifySettingsView()
    }
    .helmTheme()
}
