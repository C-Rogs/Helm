import Foundation
import GRDB

/// v16: retain App Remote's exact Spotify track identity for tempo enrichment.
enum SpotifyTrackIDSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v16_spotify_track_id") { db in
            let hasColumn = try db.columns(in: "workout_music_samples")
                .contains { $0.name == "spotify_track_id" }
            guard !hasColumn else { return }

            try db.alter(table: "workout_music_samples") { table in
                table.add(column: "spotify_track_id", .text)
            }
        }
    }
}
