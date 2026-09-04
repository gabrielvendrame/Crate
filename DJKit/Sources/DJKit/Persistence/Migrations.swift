import Foundation
import GRDB

/// Schema del database, versionato per migrazioni successive.
///
/// Ogni migrazione registrata è definitiva: si aggiunge una `v2`, non si modifica la `v1`, perché
/// il database di Gabriel contiene ore di download e non è ricreabile.
enum Migrations {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1-schema") { db in
            try db.create(table: "track") { t in
                t.primaryKey("id", .text)
                // Unico: impedisce di scaricare due volte lo stesso video.
                t.column("youtubeID", .text).notNull().unique()
                t.column("youtubeURL", .text).notNull()

                t.column("title", .text).notNull().defaults(to: "")
                t.column("artist", .text).notNull().defaults(to: "")
                t.column("album", .text).notNull().defaults(to: "")

                t.column("durationSeconds", .double).notNull().defaults(to: 0)
                t.column("sampleRate", .double).notNull().defaults(to: 0)
                t.column("channelCount", .integer).notNull().defaults(to: 0)

                t.column("bpm", .double)
                t.column("beatgridOffsetSeconds", .double)

                t.column("audioFilename", .text)
                t.column("peaksFilename", .text)
                t.column("labelImageAFilename", .text)
                t.column("labelImageBFilename", .text)

                t.column("analysisState", .text).notNull().defaults(to: AnalysisState.pending.rawValue)
                t.column("analysisError", .text)
                t.column("addedAt", .datetime).notNull()
            }
            try db.create(indexOn: "track", columns: ["addedAt"])

            try db.create(table: "cuePoint") { t in
                t.primaryKey("id", .text)
                t.column("trackID", .text).notNull()
                    .references("track", onDelete: .cascade)
                t.column("positionSeconds", .double).notNull()
                t.column("label", .text).notNull().defaults(to: "")
                t.column("note", .text).notNull().defaults(to: "")
                t.column("colorIndex", .integer).notNull().defaults(to: 0)
                // 1...8 per un hot cue. NULL per un memory cue: SQLite ammette più NULL in un
                // indice unico, quindi i memory cue restano illimitati senza clausole speciali.
                t.column("hotcueSlot", .integer)
            }
            try db.create(indexOn: "cuePoint", columns: ["trackID", "positionSeconds"])
            try db.create(
                index: "cuePoint_uniqueHotcue",
                on: "cuePoint",
                columns: ["trackID", "hotcueSlot"],
                unique: true
            )

            try db.create(table: "playlist") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("note", .text).notNull().defaults(to: "")
                t.column("createdAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "playlistItem") { t in
                t.primaryKey("id", .text)
                t.column("playlistID", .text).notNull()
                    .references("playlist", onDelete: .cascade)
                t.column("position", .integer).notNull()
                t.column("kind", .text).notNull()
                // Se la traccia sparisce dalla libreria la riga resta come segnaposto, invece di
                // aprire un buco silenzioso nella scaletta.
                t.column("trackID", .text)
                    .references("track", onDelete: .setNull)
                t.column("text", .text).notNull().defaults(to: "")
            }
            try db.create(indexOn: "playlistItem", columns: ["playlistID", "position"])
        }

        return migrator
    }
}
