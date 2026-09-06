import Foundation
import GRDB

/// Il legame fra una traccia e un tag: una riga per ogni accoppiata.
///
/// Tabella ponte e non una colonna di testo sulla traccia: un tag rinominato deve restare lo
/// stesso tag su tutti i dischi che lo portano, e cancellandolo devono sparire tutti i legami —
/// due cose che una lista di parole dentro la riga della traccia non sa fare.
public struct TrackTag: Codable, Hashable, Sendable {
    public var trackID: String
    public var tagID: String

    public init(trackID: String, tagID: String) {
        self.trackID = trackID
        self.tagID = tagID
    }
}

extension TrackTag: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "trackTag"

    public enum Columns {
        public static let trackID = Column("trackID")
        public static let tagID = Column("tagID")
    }
}
