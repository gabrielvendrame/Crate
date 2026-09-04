import Foundation
import GRDB

/// Una scaletta: una sequenza ordinata di brani e di note di passaggio.
public struct Playlist: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// Nota generale sul set: locale, serata, ordine dei dischi nella cassa.
    public var note: String
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        note: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Playlist: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "playlist"

    public enum Columns {
        public static let id = Column("id")
        public static let name = Column("name")
        public static let updatedAt = Column("updatedAt")
    }

    public static let items = hasMany(PlaylistItem.self)
        .order(PlaylistItem.Columns.position)
    public var items: QueryInterfaceRequest<PlaylistItem> { request(for: Playlist.items) }
}
