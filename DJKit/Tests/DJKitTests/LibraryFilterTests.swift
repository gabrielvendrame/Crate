import Foundation
import Testing
@testable import DJKit

@Suite("Filtro della libreria")
struct LibraryFilterTests {
    private func track(
        title: String = "",
        artist: String = "",
        album: String = "",
        bpm: Double? = 128,
        peaks: String? = "p.peaks",
        artworkA: String? = nil,
        state: AnalysisState = .ready
    ) -> Track {
        Track(
            youtubeID: UUID().uuidString,
            youtubeURL: "https://example.invalid",
            title: title,
            artist: artist,
            album: album,
            bpm: bpm,
            peaksFilename: peaks,
            labelImageAFilename: artworkA,
            analysisState: state
        )
    }

    @Test("Un filtro vuoto lascia passare tutto")
    func emptyFilterKeepsEverything() {
        let tracks = [track(title: "Uno"), track(title: "Due")]
        #expect(LibraryFilter().apply(to: tracks).count == 2)
        #expect(LibraryFilter().isActive == false)
    }

    @Test("Le parole si cercano in tutti i campi e in qualsiasi ordine")
    func matchesWordsAcrossFields() {
        let wanted = track(title: "What's A Girl To Do", artist: "Fatima Yamaha")
        let other = track(title: "Butterfly", artist: "Laesh")
        let found = LibraryFilter(text: "yamaha girl").apply(to: [wanted, other])
        #expect(found.count == 1)
        #expect(found.first?.artist == "Fatima Yamaha")
    }

    @Test("Maiuscole e accenti non contano")
    func ignoresCaseAndDiacritics() {
        let wanted = track(title: "Perché No", artist: "Ámbar")
        #expect(LibraryFilter(text: "perche").apply(to: [wanted]).count == 1)
        #expect(LibraryFilter(text: "AMBAR").apply(to: [wanted]).count == 1)
    }

    @Test("Una parola che non c'è esclude la riga, anche se le altre ci sono")
    func allWordsMustMatch() {
        let wanted = track(title: "Butterfly", artist: "Laesh")
        #expect(LibraryFilter(text: "laesh butterfly").apply(to: [wanted]).count == 1)
        #expect(LibraryFilter(text: "laesh moth").apply(to: [wanted]).isEmpty)
    }

    @Test("«Da analizzare» prende chi manca di waveform, di BPM o è in errore")
    func incompleteScope() {
        let complete = track(title: "Completa")
        let noPeaks = track(title: "Senza waveform", peaks: nil)
        let noBPM = track(title: "Senza BPM", bpm: nil)
        let broken = track(title: "Rotta", state: .failed)

        let found = LibraryFilter(scope: .incomplete)
            .apply(to: [complete, noPeaks, noBPM, broken])
            .map(\.title)
        #expect(found == ["Senza waveform", "Senza BPM", "Rotta"])
    }

    @Test("I due filtri sull'etichetta si dividono la libreria")
    func artworkScopes() {
        let withPhoto = track(title: "Con foto", artworkA: "a.jpg")
        let without = track(title: "Senza foto")
        #expect(LibraryFilter(scope: .withArtwork).apply(to: [withPhoto, without]).count == 1)
        #expect(LibraryFilter(scope: .withoutArtwork).apply(to: [withPhoto, without]).count == 1)
    }

    @Test("Testo e sottoinsieme si applicano insieme")
    func textAndScopeCombine() {
        let wanted = track(title: "Butterfly", bpm: nil)
        let sameTitleComplete = track(title: "Butterfly reprise")
        let found = LibraryFilter(text: "butterfly", scope: .incomplete)
            .apply(to: [wanted, sameTitleComplete])
        #expect(found.count == 1)
        #expect(found.first?.bpm == nil)
    }
}
