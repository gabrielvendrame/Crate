import Foundation
import GRDB

/// Letture e scritture sulle scalette e sulle loro righe.
public struct PlaylistRepository: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Scalette

    public func createPlaylist(name: String) async throws -> Playlist {
        let playlist = Playlist(name: name)
        try await database.writer.write { db in
            var inserted = playlist
            try inserted.insert(db)
        }
        return playlist
    }

    public func save(_ playlist: Playlist) async throws {
        try await database.writer.write { db in
            var playlist = playlist
            playlist.updatedAt = Date()
            try playlist.save(db)
        }
    }

    public func allPlaylists() async throws -> [Playlist] {
        try await database.reader.read { db in
            try Playlist.order(Playlist.Columns.name).fetchAll(db)
        }
    }

    public func deletePlaylist(id: String) async throws {
        _ = try await database.writer.write { db in
            try Playlist.deleteOne(db, key: id)
        }
    }

    public func observeAllPlaylists() -> ValueObservation<ValueReducers.Fetch<[Playlist]>> {
        ValueObservation.tracking { db in
            try Playlist.order(Playlist.Columns.name).fetchAll(db)
        }
    }

    // MARK: - Righe

    /// Le righe della scaletta già risolte con la traccia a cui puntano.
    public func entries(playlistID: String) async throws -> [PlaylistEntry] {
        try await database.reader.read { db in
            try Self.fetchEntries(db, playlistID: playlistID)
        }
    }

    public func observeEntries(playlistID: String) -> ValueObservation<ValueReducers.Fetch<[PlaylistEntry]>> {
        ValueObservation.tracking { db in
            try Self.fetchEntries(db, playlistID: playlistID)
        }
    }

    private static func fetchEntries(_ db: Database, playlistID: String) throws -> [PlaylistEntry] {
        let items = try PlaylistItem
            .filter(PlaylistItem.Columns.playlistID == playlistID)
            .order(PlaylistItem.Columns.position)
            .fetchAll(db)

        let trackIDs = Set(items.compactMap(\.trackID))
        let tracks = try Track.filter(keys: trackIDs).fetchAll(db)
        let tracksByID = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, $0) })

        return items.map { item in
            PlaylistEntry(item: item, track: item.trackID.flatMap { tracksByID[$0] })
        }
    }

    /// Accoda un brano in fondo alla scaletta.
    @discardableResult
    public func appendTrack(_ trackID: String, to playlistID: String) async throws -> PlaylistItem {
        try await insert(kind: .track, trackID: trackID, text: "", playlistID: playlistID, at: nil)
    }

    /// Inserisce una nota. Con `position` a `nil` finisce in fondo, altrimenti si incunea nel
    /// punto indicato facendo scorrere le righe successive.
    @discardableResult
    public func insertNote(
        _ text: String = "",
        into playlistID: String,
        at position: Int? = nil
    ) async throws -> PlaylistItem {
        try await insert(kind: .note, trackID: nil, text: text, playlistID: playlistID, at: position)
    }

    @discardableResult
    public func insertTrack(
        _ trackID: String,
        into playlistID: String,
        at position: Int
    ) async throws -> PlaylistItem {
        try await insert(kind: .track, trackID: trackID, text: "", playlistID: playlistID, at: position)
    }

    private func insert(
        kind: PlaylistItemKind,
        trackID: String?,
        text: String,
        playlistID: String,
        at position: Int?
    ) async throws -> PlaylistItem {
        try await database.writer.write { db in
            let count = try PlaylistItem
                .filter(PlaylistItem.Columns.playlistID == playlistID)
                .fetchCount(db)
            let index = min(max(position ?? count, 0), count)

            // Fa spazio: le righe da `index` in poi scalano di uno.
            try db.execute(
                sql: """
                    UPDATE playlistItem SET position = position + 1
                    WHERE playlistID = ? AND position >= ?
                    """,
                arguments: [playlistID, index]
            )

            var item = switch kind {
            case .track:
                PlaylistItem.track(playlistID: playlistID, position: index, trackID: trackID ?? "")
            case .note:
                PlaylistItem.note(playlistID: playlistID, position: index, text: text)
            }
            try item.insert(db)
            try Self.touch(db, playlistID: playlistID)
            return item
        }
    }

    public func save(_ item: PlaylistItem) async throws {
        try await database.writer.write { db in
            var item = item
            try item.save(db)
            try Self.touch(db, playlistID: item.playlistID)
        }
    }

    /// Rimuove una riga e ricompatta le posizioni, così `position` resta densa.
    public func deleteItem(id: String, in playlistID: String) async throws {
        try await database.writer.write { db in
            _ = try PlaylistItem.deleteOne(db, key: id)
            try Self.compactPositions(db, playlistID: playlistID)
            try Self.touch(db, playlistID: playlistID)
        }
    }

    /// Riscrive l'ordine della scaletta a partire dalla sequenza di identificativi risultante dal
    /// drag & drop. Riscrittura densa su tutta la playlist: le scalette sono corte e così si evita
    /// la deriva progressiva degli indici frazionari.
    public func reorder(playlistID: String, orderedItemIDs: [String]) async throws {
        try await database.writer.write { db in
            for (index, itemID) in orderedItemIDs.enumerated() {
                try db.execute(
                    sql: "UPDATE playlistItem SET position = ? WHERE id = ? AND playlistID = ?",
                    arguments: [index, itemID, playlistID]
                )
            }
            // Eventuali righe non citate (concorrenza, id sconosciuti) finiscono in coda invece di
            // collidere sulle posizioni appena assegnate.
            try Self.compactPositions(db, playlistID: playlistID)
            try Self.touch(db, playlistID: playlistID)
        }
    }

    private static func compactPositions(_ db: Database, playlistID: String) throws {
        let items = try PlaylistItem
            .filter(PlaylistItem.Columns.playlistID == playlistID)
            .order(PlaylistItem.Columns.position)
            .fetchAll(db)
        for (index, item) in items.enumerated() where item.position != index {
            try db.execute(
                sql: "UPDATE playlistItem SET position = ? WHERE id = ?",
                arguments: [index, item.id]
            )
        }
    }

    private static func touch(_ db: Database, playlistID: String) throws {
        try db.execute(
            sql: "UPDATE playlist SET updatedAt = ? WHERE id = ?",
            arguments: [Date(), playlistID]
        )
    }
}
