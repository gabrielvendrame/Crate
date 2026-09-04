import Foundation
import GRDB

public enum PlaylistItemKind: String, Codable, Sendable {
    case track
    case note
}

extension PlaylistItemKind: DatabaseValueConvertible {}

/// Una riga di scaletta: o un brano, o una nota libera fra un brano e l'altro.
///
/// Le note sono righe autonome anziché un campo attaccato alla traccia, così se ne possono
/// mettere più d'una fra due pezzi — o una in testa alla scaletta — e si riordinano col drag &
/// drop insieme ai brani.
///
/// `position` è **densa** (0, 1, 2, …) e viene riscritta su tutta la playlist a ogni drop. Le
/// scalette sono corte, quindi non serve niente di più furbo e si evita la deriva progressiva
/// degli indici frazionari.
public struct PlaylistItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var playlistID: String
    public var position: Int
    public var kind: PlaylistItemKind
    /// Valorizzato solo per `kind == .track`. Diventa `nil` se la traccia viene eliminata dalla
    /// libreria: la riga resta come segnaposto invece di far sparire pezzi di scaletta.
    public var trackID: String?
    /// Valorizzato solo per `kind == .note`.
    public var text: String

    private init(
        id: String,
        playlistID: String,
        position: Int,
        kind: PlaylistItemKind,
        trackID: String?,
        text: String
    ) {
        self.id = id
        self.playlistID = playlistID
        self.position = position
        self.kind = kind
        self.trackID = trackID
        self.text = text
    }

    public static func track(
        id: String = UUID().uuidString,
        playlistID: String,
        position: Int,
        trackID: String
    ) -> PlaylistItem {
        PlaylistItem(
            id: id, playlistID: playlistID, position: position,
            kind: .track, trackID: trackID, text: ""
        )
    }

    public static func note(
        id: String = UUID().uuidString,
        playlistID: String,
        position: Int,
        text: String = ""
    ) -> PlaylistItem {
        PlaylistItem(
            id: id, playlistID: playlistID, position: position,
            kind: .note, trackID: nil, text: text
        )
    }
}

extension PlaylistItem: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "playlistItem"

    public enum Columns {
        public static let id = Column("id")
        public static let playlistID = Column("playlistID")
        public static let position = Column("position")
        public static let kind = Column("kind")
        public static let trackID = Column("trackID")
    }

    public static let playlist = belongsTo(Playlist.self)
    public static let trackRecord = belongsTo(Track.self)
}

/// Una riga di scaletta già risolta con la traccia a cui punta, pronta per la UI.
public struct PlaylistEntry: Identifiable, Hashable, Sendable {
    public var item: PlaylistItem
    public var track: Track?

    public var id: String { item.id }

    public init(item: PlaylistItem, track: Track?) {
        self.item = item
        self.track = track
    }
}
