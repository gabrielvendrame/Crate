import Foundation
import GRDB

/// Letture e scritture sulle tracce e sui loro cue point.
public struct TrackRepository: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Tracce

    public func save(_ track: Track) async throws {
        // La copia mutabile vive dentro la closure: Swift 6 non ammette di catturare una `var`
        // esterna in codice che gira su un altro thread.
        try await database.writer.write { db in
            var track = track
            try track.save(db)
        }
    }

    public func track(id: String) async throws -> Track? {
        try await database.reader.read { db in
            try Track.fetchOne(db, key: id)
        }
    }

    public func track(youtubeID: String) async throws -> Track? {
        try await database.reader.read { db in
            try Track.filter(Track.Columns.youtubeID == youtubeID).fetchOne(db)
        }
    }

    public func allTracks() async throws -> [Track] {
        try await database.reader.read { db in
            try Track.order(Track.Columns.addedAt.desc).fetchAll(db)
        }
    }

    /// Cancella la traccia e, a cascata, i suoi cue point. I file su disco vanno rimossi a parte:
    /// il repository non tocca il filesystem.
    public func deleteTrack(id: String) async throws {
        _ = try await database.writer.write { db in
            try Track.deleteOne(db, key: id)
        }
    }

    public func updateAnalysisState(
        trackID: String,
        to state: AnalysisState,
        error: String? = nil
    ) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE track SET analysisState = ?, analysisError = ? WHERE id = ?",
                arguments: [state.rawValue, error, trackID]
            )
        }
    }

    /// Segna l'analisi conclusa scrivendo solo le sue colonne.
    ///
    /// Un `save` della traccia intera cancellerebbe le correzioni fatte nell'ispettore mentre
    /// l'analisi girava: sono minuti, non millisecondi.
    ///
    /// Il tempo si scrive **solo se è stato rilevato**: su un pezzo che non ha una pulsazione
    /// riconoscibile l'analisi torna senza BPM, e in quel caso una griglia messa a mano in
    /// precedenza deve restare dov'è invece di essere azzerata.
    public func updateAnalysis(
        trackID: String,
        peaksFilename: String?,
        tempo: TempoEstimate?
    ) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    UPDATE track
                    SET peaksFilename = ?, analysisState = ?, analysisError = NULL
                    WHERE id = ?
                    """,
                arguments: [peaksFilename, AnalysisState.ready.rawValue, trackID]
            )
            guard let tempo else { return }
            try db.execute(
                sql: "UPDATE track SET bpm = ?, beatgridOffsetSeconds = ? WHERE id = ?",
                arguments: [tempo.bpm, tempo.beatgridOffsetSeconds, trackID]
            )
        }
    }

    /// Scrive la griglia corretta a mano: BPM e primo downbeat, niente altro.
    ///
    /// `nil` cancella la griglia — è il modo di dire "questo pezzo non ha un tempo utile" senza
    /// lasciare in tabella un numero inventato che il quantize prenderebbe per buono.
    public func updateBeatgrid(
        trackID: String,
        bpm: Double?,
        beatgridOffsetSeconds: Double?
    ) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "UPDATE track SET bpm = ?, beatgridOffsetSeconds = ? WHERE id = ?",
                arguments: [bpm, beatgridOffsetSeconds, trackID]
            )
        }
    }

    /// Osservazione della libreria intera, per tenere aggiornata la tabella senza ricaricarla a mano.
    public func observeAllTracks() -> ValueObservation<ValueReducers.Fetch<[Track]>> {
        ValueObservation.tracking { db in
            try Track.order(Track.Columns.addedAt.desc).fetchAll(db)
        }
    }

    // MARK: - Cue point

    public func cuePoints(trackID: String) async throws -> [CuePoint] {
        try await database.reader.read { db in
            try CuePoint
                .filter(CuePoint.Columns.trackID == trackID)
                .order(CuePoint.Columns.positionSeconds)
                .fetchAll(db)
        }
    }

    public func save(_ cuePoint: CuePoint) async throws {
        try await database.writer.write { db in
            var cuePoint = cuePoint
            try cuePoint.save(db)
        }
    }

    public func deleteCuePoint(id: String) async throws {
        _ = try await database.writer.write { db in
            try CuePoint.deleteOne(db, key: id)
        }
    }

    /// Assegna uno slot di hot cue liberando prima chi lo occupava: l'indice unico su
    /// `(trackID, hotcueSlot)` rifiuterebbe altrimenti la scrittura.
    public func assignHotCue(_ cuePoint: CuePoint, toSlot slot: Int) async throws {
        precondition(CuePoint.hotcueSlotRange.contains(slot), "slot hot cue fuori range: \(slot)")
        try await database.writer.write { db in
            var cuePoint = cuePoint
            cuePoint.hotcueSlot = slot
            try db.execute(
                sql: """
                    UPDATE cuePoint SET hotcueSlot = NULL
                    WHERE trackID = ? AND hotcueSlot = ? AND id <> ?
                    """,
                arguments: [cuePoint.trackID, slot, cuePoint.id]
            )
            try cuePoint.save(db)
        }
    }

    public func observeCuePoints(trackID: String) -> ValueObservation<ValueReducers.Fetch<[CuePoint]>> {
        ValueObservation.tracking { db in
            try CuePoint
                .filter(CuePoint.Columns.trackID == trackID)
                .order(CuePoint.Columns.positionSeconds)
                .fetchAll(db)
        }
    }
}
