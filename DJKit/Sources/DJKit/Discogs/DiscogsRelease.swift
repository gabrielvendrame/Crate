import Foundation

/// Un risultato di ricerca su Discogs: quel tanto che basta a riconoscere il disco giusto fra
/// dieci copertine, e la copertina stessa.
///
/// Non è un modello completo della risposta di Discogs, ed è voluto: qui serve **scegliere una
/// foto**, non catalogare. Tracklist, crediti e prezzi non entrano in libreria — i metadati di
/// questa app sono quattro, per scelta di scope.
public struct DiscogsRelease: Identifiable, Hashable, Sendable {
    public let id: Int
    /// Come lo scrive Discogs: di solito "Artista - Titolo".
    public let title: String
    public let year: String?
    public let label: String?
    public let catalogNumber: String?
    /// "Vinyl", "12\"", "LP"… serve a riconoscere a colpo d'occhio l'edizione in vinile.
    public let formats: [String]
    public let country: String?
    /// Miniatura per la griglia di scelta, e immagine piena da salvare come etichetta.
    public let thumbnailURL: URL?
    public let coverURL: URL?

    public init(
        id: Int,
        title: String,
        year: String? = nil,
        label: String? = nil,
        catalogNumber: String? = nil,
        formats: [String] = [],
        country: String? = nil,
        thumbnailURL: URL? = nil,
        coverURL: URL? = nil
    ) {
        self.id = id
        self.title = title
        self.year = year
        self.label = label
        self.catalogNumber = catalogNumber
        self.formats = formats
        self.country = country
        self.thumbnailURL = thumbnailURL
        self.coverURL = coverURL
    }

    /// Riga di sottotitolo sotto la copertina: etichetta, numero di catalogo, anno e formato,
    /// saltando ciò che manca.
    public var details: String {
        var parts: [String] = []
        if let label { parts.append(label) }
        if let catalogNumber, !catalogNumber.isEmpty, catalogNumber != "none" {
            parts.append(catalogNumber)
        }
        if let year, !year.isEmpty { parts.append(year) }
        if let country, !country.isEmpty { parts.append(country) }
        let format = formats.filter { !$0.isEmpty }.prefix(2).joined(separator: " ")
        if !format.isEmpty { parts.append(format) }
        return parts.joined(separator: " · ")
    }

    /// Il nome dell'album, ricavato dal titolo della release.
    ///
    /// Discogs scrive il titolo come «Artista - Album», quindi l'album è ciò che sta dopo il primo
    /// trattino: separare sul **primo** e non sull'ultimo è quello che salva i titoli che il
    /// trattino ce l'hanno dentro («Kölsch - Der Alte - Remixes»). Senza trattino il titolo è già
    /// l'album e si prende intero, che è il caso delle compilation catalogate senza artista.
    ///
    /// Serve a riempire il campo Album quando si sceglie l'edizione: fin qui da quella scelta si
    /// prendeva solo la copertina, e il nome del disco — che Discogs sa con certezza — restava da
    /// scrivere a mano.
    public var albumTitle: String? {
        guard let range = title.range(of: " - ") else {
            let whole = title.trimmingCharacters(in: .whitespacesAndNewlines)
            return whole.isEmpty ? nil : whole
        }
        let album = title[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        return album.isEmpty ? nil : album
    }

    /// Un'edizione in vinile: è quella che interessa a chi prepara un set da suonare sui piatti.
    public var isVinyl: Bool {
        formats.contains { $0.localizedCaseInsensitiveContains("vinyl") }
    }
}
