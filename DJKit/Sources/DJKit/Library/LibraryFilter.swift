import Foundation

/// Come è filtrata la libreria: un testo da cercare e un eventuale sottoinsieme.
///
/// Sta in `DJKit` e non nel target app perché è **logica pura**, ed è il genere di logica che si
/// sbaglia in silenzio: una normalizzazione fatta male non fa crashare niente, fa solo sparire
/// dalla ricerca il pezzo che si sta cercando. Qui si prova con `swift test` in un secondo.
public struct LibraryFilter: Equatable, Sendable {
    public var text: String
    public var scope: Scope
    /// Il tag da cui si guarda la libreria, scelto nella barra laterale. `nil` = tutti.
    ///
    /// **Una dimensione a sé e non un quinto caso di `Scope`**, come si era ipotizzato scrivendo
    /// il task: scope e tag sono ortogonali, e «senza etichetta» *e* «funky» è una domanda che si
    /// fa davvero — con un picker solo non si potrebbe formulare. Il prezzo è un campo in più
    /// qui; il guadagno è che i due comandi non si contendono lo stesso stato.
    public var tagID: String?

    public init(text: String = "", scope: Scope = .all, tagID: String? = nil) {
        self.text = text
        self.scope = scope
        self.tagID = tagID
    }

    /// I sottoinsiemi che si vanno davvero a cercare, e nessun altro.
    ///
    /// Niente filtro per BPM o per durata: la libreria di chi prepara set in vinile è di decine di
    /// brani, non di decine di migliaia, e ogni filtro in più è una riga di interfaccia che ruba
    /// spazio alla tabella.
    public enum Scope: String, CaseIterable, Identifiable, Sendable {
        case all
        case incomplete
        case withArtwork
        case withoutArtwork

        public var id: String { rawValue }

        public var label: String {
            switch self {
            case .all: "Tutte"
            case .incomplete: "Da analizzare"
            case .withArtwork: "Con etichetta"
            case .withoutArtwork: "Senza etichetta"
            }
        }
    }

    public var isActive: Bool {
        !text.trimmingCharacters(in: .whitespaces).isEmpty || scope != .all || tagID != nil
    }

    /// `tagIDsByTrack` è la mappa dei legami, letta una volta sola: il filtro non ha un database
    /// da interrogare, e non deve averlo — resta una funzione pura, provata in un secondo.
    public func apply(
        to tracks: [Track],
        tagIDsByTrack: [String: Set<String>] = [:]
    ) -> [Track] {
        guard isActive else { return tracks }
        return tracks.filter {
            matchesScope($0) && matchesTag($0, tagIDsByTrack: tagIDsByTrack) && matchesText($0)
        }
    }

    private func matchesTag(_ track: Track, tagIDsByTrack: [String: Set<String>]) -> Bool {
        guard let tagID else { return true }
        return tagIDsByTrack[track.id]?.contains(tagID) ?? false
    }

    private func matchesScope(_ track: Track) -> Bool {
        switch scope {
        case .all:
            true
        case .incomplete:
            track.analysisState == .failed || track.peaksFilename == nil || track.bpm == nil
        case .withArtwork:
            track.labelImageAFilename != nil || track.labelImageBFilename != nil
        case .withoutArtwork:
            track.labelImageAFilename == nil && track.labelImageBFilename == nil
        }
    }

    /// Tutte le parole scritte devono comparire da qualche parte fra titolo, artista e album.
    ///
    /// A parole e non come sottostringa unica: cercando "yamaha girl" si trova
    /// "Fatima Yamaha — What's A Girl To Do" anche se le due parole stanno in campi diversi e in
    /// ordine inverso, che è come ci si ricorda un pezzo. Il confronto ignora maiuscole **e
    /// accenti**: su una tastiera italiana si scrive "perche" e il titolo dice "perché".
    private func matchesText(_ track: Track) -> Bool {
        let words = Self.normalize(text).split(separator: " ")
        guard !words.isEmpty else { return true }
        let haystack = Self.normalize(
            [track.title, track.artist, track.album, track.youtubeID].joined(separator: " ")
        )
        return words.allSatisfy { haystack.contains($0) }
    }

    public static func normalize(_ value: String) -> String {
        value.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}
