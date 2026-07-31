import Foundation
import GRDB

enum WorkoutMusicSchemaMigration {
    static func register(on migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v14_workout_music_samples") { db in
            try db.create(table: "workout_music_samples") { table in
                table.column("id", .text).primaryKey()
                table.column("session_id", .text).notNull().indexed()
                table.column("sampled_at", .text).notNull().indexed()
                table.column("title", .text)
                table.column("artist", .text)
                table.column("album", .text)
                table.column("genre", .text)
                table.column("bpm", .double)
                table.column("playback_rate", .double)
                table.column("source", .text).notNull()
            }
        }
    }
}
