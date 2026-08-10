import Foundation
import GRDB

/// v16: retain App Remote's exact Spotify track identity for tempo enrichment.
enum SpotifyTrackIDSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v16_spotify_track_id") { db in
            try db.alter(table: "workout_music_samples") { table in
                table.add(column: "spotify_track_id", .text)
            }
        }
    }
}
