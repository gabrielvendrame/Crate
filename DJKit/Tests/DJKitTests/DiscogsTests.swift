import Foundation
import Testing
@testable import DJKit

@Suite("Ricerca su Discogs")
struct DiscogsTests {

    // MARK: - Costruzione della ricerca

    @Test("Il primo tentativo è artista + brano, solo vinile")
    func firstAttemptIsTheNarrowest() {
        let attempts = DiscogsQuery.attempts(artist: "Fatima Yamaha", title: "What's A Girl To Do")
        let first = attempts.first
        #expect(first?.parameters["artist"] == "Fatima Yamaha")
        #expect(first?.parameters["track"] == "What's A Girl To Do")
        #expect(first?.vinylOnly == true)
    }

    @Test("Dopo il titolo intero si riprova senza le parentesi")
    func widensByDroppingParentheticals() {
        let attempts = DiscogsQuery.attempts(
            artist: "Pushin' Boundaries", title: "Keep It Goin' (Matt Schrewd Mix)"
        )
        let tracks = attempts.compactMap { $0.parameters["track"] }
        #expect(tracks.contains("Keep It Goin' (Matt Schrewd Mix)"))
        #expect(tracks.contains("Keep It Goin'"))
    }

    @Test("L'ultimo tentativo è largo: testo libero e qualsiasi formato")
    func lastAttemptIsTheWidest() {
        let attempts = DiscogsQuery.attempts(artist: "Laesh", title: "Butterfly")
        let last = attempts.last
        #expect(last?.parameters["q"] == "Laesh Butterfly")
        #expect(last?.vinylOnly == false)
    }

    @Test("Senza artista si cerca comunque, solo a testo libero")
    func worksWithoutArtist() {
        let attempts = DiscogsQuery.attempts(artist: "", title: "Butterfly")
        #expect(!attempts.isEmpty)
        #expect(attempts.allSatisfy { $0.parameters["artist"] == nil })
        #expect(attempts.first?.parameters["q"] == "Butterfly")
    }

    @Test("Senza né artista né titolo non c'è niente da cercare")
    func nothingToSearch() {
        #expect(DiscogsQuery.attempts(artist: "  ", title: "").isEmpty)
    }

    @Test("Il rumore dei titoli di YouTube viene tolto")
    func stripsYouTubeNoise() {
        let cleaned = DiscogsQuery.clean("Butterfly (Official Video) | HD")
        #expect(!cleaned.localizedCaseInsensitiveContains("official video"))
        #expect(!cleaned.contains("|"))
        #expect(cleaned.contains("Butterfly"))
        // Niente spazi doppi lasciati dalle sostituzioni.
        #expect(!cleaned.contains("  "))
    }

    // MARK: - Decodifica della risposta

    /// Una risposta ridotta ma con la stessa forma di quella vera, compresi i campi che Discogs
    /// manda vuoti invece di omettere.
    private static let sample = Data("""
    {
      "results": [
        {
          "id": 1234,
          "title": "Fatima Yamaha - What's A Girl To Do",
          "year": "2004",
          "label": ["Magnetron Music", "Dekmantel"],
          "catno": "DONE031",
          "format": ["Vinyl", "12\\"", "45 RPM"],
          "country": "Netherlands",
          "thumb": "https://img.discogs.invalid/thumb.jpg",
          "cover_image": "https://img.discogs.invalid/cover.jpg"
        },
        {
          "id": 5678,
          "title": "Senza immagini",
          "year": "",
          "label": [],
          "catno": "none",
          "format": ["CD"],
          "country": "",
          "thumb": "",
          "cover_image": " "
        }
      ]
    }
    """.utf8)

    @Test("L'album esce dal titolo della release, tagliato sul primo trattino")
    func albumFromTitle() {
        #expect(DiscogsRelease(id: 1, title: "Kölsch - Speicher 70").albumTitle == "Speicher 70")
        // Il trattino dentro il titolo resta dov'è: si taglia sul primo, non sull'ultimo.
        #expect(
            DiscogsRelease(id: 2, title: "Kölsch - Der Alte - Remixes").albumTitle
                == "Der Alte - Remixes"
        )
        // Senza artista davanti il titolo è già l'album — le compilation sono catalogate così.
        #expect(DiscogsRelease(id: 3, title: "Speicher 70").albumTitle == "Speicher 70")
        #expect(DiscogsRelease(id: 4, title: "Kölsch -   ").albumTitle == nil)
        #expect(DiscogsRelease(id: 5, title: "  ").albumTitle == nil)
    }

    @Test("La risposta di ricerca si legge nei campi che servono")
    func decodesSearchResults() throws {
        let releases = try DiscogsClient.decodeSearch(Self.sample)
        #expect(releases.count == 2)

        let first = releases[0]
        #expect(first.id == 1234)
        #expect(first.label == "Magnetron Music")
        #expect(first.catalogNumber == "DONE031")
        #expect(first.isVinyl)
        #expect(first.coverURL?.absoluteString == "https://img.discogs.invalid/cover.jpg")
        #expect(first.details.contains("Magnetron Music"))
        #expect(first.details.contains("DONE031"))
        #expect(first.details.contains("2004"))
    }

    @Test("Immagini vuote e catalogo «none» non diventano dati finti")
    func handlesEmptyFields() throws {
        let releases = try DiscogsClient.decodeSearch(Self.sample)
        let second = releases[1]
        #expect(second.thumbnailURL == nil)
        // Discogs manda uno spazio, e `URL(string:)` lo accetterebbe.
        #expect(second.coverURL == nil)
        #expect(!second.isVinyl)
        #expect(!second.details.contains("none"))
    }

    @Test("Una risposta illeggibile è un errore, non una lista vuota")
    func rejectsMalformedResponse() {
        #expect(throws: DiscogsError.self) {
            try DiscogsClient.decodeSearch(Data("non è json".utf8))
        }
    }

    // MARK: - Token

    @Test("Il token si scrive, si rilegge e si cancella")
    func tokenRoundTrip() throws {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "CrateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let paths = LibraryPaths(root: root)
        try paths.createDirectories()
        defer { try? FileManager.default.removeItem(at: root) }

        let store = DiscogsToken(paths: paths)
        #expect(store.read() == nil)

        try store.write("  abcdef123456  ")
        #expect(store.read() == "abcdef123456", "gli spazi attorno vanno tolti")

        // Solo l'utente può leggerlo: è pur sempre una credenziale.
        let attributes = try FileManager.default.attributesOfItem(
            atPath: root.appending(path: "discogs-token").path
        )
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)

        try store.write("   ")
        #expect(store.read() == nil, "scrivere il vuoto cancella il token")
    }
}

/// Test che parlano davvero con Discogs. Esclusi dalla suite normale: richiedono rete e un token
/// personale, che non sta nel repository.
///
///     CRATE_DISCOGS_TOKEN=... swift test --package-path DJKit --filter DiscogsIntegration
@Suite("Discogs — integrazione")
struct DiscogsIntegrationTests {
    private var token: String? { ProcessInfo.processInfo.environment["CRATE_DISCOGS_TOKEN"] }

    @Test(
        "Un disco noto si trova, ed è in vinile",
        .enabled(if: ProcessInfo.processInfo.environment["CRATE_DISCOGS_TOKEN"] != nil)
    )
    func findsKnownRelease() async throws {
        let client = DiscogsClient(token: try #require(token))
        let releases = try await client.search(
            attempts: DiscogsQuery.attempts(artist: "Fatima Yamaha", title: "What's A Girl To Do")
        )
        #expect(!releases.isEmpty)
        #expect(releases.contains { $0.isVinyl })
        #expect(releases.contains { $0.coverURL != nil })
    }

    @Test(
        "Un token sbagliato viene riconosciuto come tale",
        .enabled(if: ProcessInfo.processInfo.environment["CRATE_DISCOGS_TOKEN"] != nil)
    )
    func rejectsBadToken() async {
        let client = DiscogsClient(token: "questo-non-e-un-token")
        await #expect(throws: DiscogsError.self) {
            try await client.search(attempts: DiscogsQuery.attempts(artist: "Laesh", title: "Butterfly"))
        }
    }
}
