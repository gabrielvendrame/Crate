import Foundation
import GRDB

/// Un brano nella libreria: l'audio scaricato da YouTube più tutto ciò che ci gira attorno.
///
/// I nomi dei file sono relativi alle cartelle di `LibraryPaths`, mai percorsi assoluti: la
/// libreria deve restare spostabile e il database indipendente dalla home dell'utente.
public struct Track: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    /// Identificativo del video YouTube (es. `dQw4w9WgXcQ`), unico in tabella: impedisce i doppioni.
    public var youtubeID: String
    public var youtubeURL: String

    public var title: String
    public var artist: String
    public var album: String

    public var durationSeconds: Double
    public var sampleRate: Double
    public var channelCount: Int

    /// Tempo rilevato o corretto a mano. `nil` finché l'analisi non è passata.
    public var bpm: Double?
    /// Posizione del primo downbeat: insieme al BPM definisce l'intera beatgrid.
    public var beatgridOffsetSeconds: Double?

    public var audioFilename: String?
    public var peaksFilename: String?
    /// Foto dell'etichetta, lato A e lato B del vinile.
    public var labelImageAFilename: String?
    public var labelImageBFilename: String?

    public var analysisState: AnalysisState
    public var analysisError: String?
    public var addedAt: Date

    public init(
        id: String = UUID().uuidString,
        youtubeID: String,
        youtubeURL: String,
        title: String = "",
        artist: String = "",
        album: String = "",
        durationSeconds: Double = 0,
        sampleRate: Double = 0,
        channelCount: Int = 0,
        bpm: Double? = nil,
        beatgridOffsetSeconds: Double? = nil,
        audioFilename: String? = nil,
        peaksFilename: String? = nil,
        labelImageAFilename: String? = nil,
        labelImageBFilename: String? = nil,
        analysisState: AnalysisState = .pending,
        analysisError: String? = nil,
        addedAt: Date = Date()
    ) {
        self.id = id
        self.youtubeID = youtubeID
        self.youtubeURL = youtubeURL
        self.title = title
        self.artist = artist
        self.album = album
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
        self.channelCount = channelCount
        self.bpm = bpm
        self.beatgridOffsetSeconds = beatgridOffsetSeconds
        self.audioFilename = audioFilename
        self.peaksFilename = peaksFilename
        self.labelImageAFilename = labelImageAFilename
        self.labelImageBFilename = labelImageBFilename
        self.analysisState = analysisState
        self.analysisError = analysisError
        self.addedAt = addedAt
    }

    /// La griglia della traccia, se ne ha una. `nil` finché il tempo non è stato rilevato o
    /// scritto a mano: è il segnale che il quantize non ha niente a cui agganciarsi.
    ///
    /// Un offset mancante vale zero — una traccia con il BPM ma senza downbeat è comunque
    /// meglio di nessuna griglia, e il downbeat si trascina in un gesto.
    public var beatgrid: Beatgrid? {
        guard let bpm else { return nil }
        return Beatgrid(bpm: bpm, offsetSeconds: beatgridOffsetSeconds ?? 0)
    }

    /// Etichetta compatta per liste e deck: "Artista — Titolo", con i pezzi mancanti omessi.
    public var displayName: String {
        switch (artist.isEmpty, title.isEmpty) {
        case (false, false): "\(artist) — \(title)"
        case (true, false): title
        case (false, true): artist
        case (true, true): youtubeID
        }
    }
}

extension Track: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "track"

    public enum Columns {
        public static let id = Column("id")
        public static let youtubeID = Column("youtubeID")
        public static let title = Column("title")
        public static let artist = Column("artist")
        public static let album = Column("album")
        public static let bpm = Column("bpm")
        public static let analysisState = Column("analysisState")
        public static let addedAt = Column("addedAt")
    }

    public static let cuePoints = hasMany(CuePoint.self)
    public var cuePoints: QueryInterfaceRequest<CuePoint> { request(for: Track.cuePoints) }
}
