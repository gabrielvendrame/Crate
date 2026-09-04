import Foundation
import GRDB

/// Un punto memorizzato dentro una traccia, con la nota che spiega perché è lì.
///
/// Due specie nello stesso tipo: gli **hot cue** occupano uno slot da 1 a 8 e sono richiamabili
/// dai tasti numerici; i **memory cue** hanno `hotcueSlot` a `nil`, sono illimitati e compaiono
/// solo come marker sulla waveform.
public struct CuePoint: Identifiable, Codable, Hashable, Sendable {
    public static let hotcueSlotRange = 1...8

    public var id: String
    public var trackID: String
    public var positionSeconds: Double
    /// Nome breve mostrato sul marker (es. "drop", "break").
    public var label: String
    /// Annotazione estesa: cosa fare qui, come ci si arriva, con cosa lega.
    public var note: String
    public var colorIndex: Int
    /// Da 1 a 8 per un hot cue, `nil` per un memory cue.
    public var hotcueSlot: Int?

    public init(
        id: String = UUID().uuidString,
        trackID: String,
        positionSeconds: Double,
        label: String = "",
        note: String = "",
        colorIndex: Int = 0,
        hotcueSlot: Int? = nil
    ) {
        self.id = id
        self.trackID = trackID
        self.positionSeconds = positionSeconds
        self.label = label
        self.note = note
        self.colorIndex = colorIndex
        self.hotcueSlot = hotcueSlot
    }

    public var isHotCue: Bool { hotcueSlot != nil }
}

extension CuePoint: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "cuePoint"

    public enum Columns {
        public static let id = Column("id")
        public static let trackID = Column("trackID")
        public static let positionSeconds = Column("positionSeconds")
        public static let hotcueSlot = Column("hotcueSlot")
    }

    public static let track = belongsTo(Track.self)
}
