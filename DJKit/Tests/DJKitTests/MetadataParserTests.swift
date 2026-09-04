import Foundation
import Testing
@testable import DJKit

@Suite("Parsing dei titoli YouTube")
struct MetadataParserTests {

    @Test("Separa artista e titolo sul trattino")
    func splitsOnDash() {
        let parsed = MetadataParser.parse(videoTitle: "Aphex Twin - Windowlicker", uploader: "Warp")
        #expect(parsed.artist == "Aphex Twin")
        #expect(parsed.title == "Windowlicker")
    }

    @Test("Funziona anche con trattino lungo, barra verticale e punto centrale",
          arguments: [
            "Boards of Canada – Roygbiv",
            "Boards of Canada — Roygbiv",
            "Boards of Canada | Roygbiv",
            "Boards of Canada • Roygbiv",
          ])
    func splitsOnOtherSeparators(_ input: String) {
        let parsed = MetadataParser.parse(videoTitle: input, uploader: nil)
        #expect(parsed.artist == "Boards of Canada")
        #expect(parsed.title == "Roygbiv")
    }

    @Test("Il rumore fra parentesi sparisce",
          arguments: [
            "Artista - Brano (Official Video)",
            "Artista - Brano (Official Music Video)",
            "Artista - Brano [Official Audio]",
            "Artista - Brano (HD)",
            "Artista - Brano (Lyrics)",
            "Artista - Brano (Remastered 2019)",
            "Artista - Brano (Full Album)",
            "Artista - Brano (Free Download)",
            "Artista - Brano (Visualizer)",
          ])
    func removesNoise(_ input: String) {
        let parsed = MetadataParser.parse(videoTitle: input, uploader: nil)
        #expect(parsed.artist == "Artista")
        #expect(parsed.title == "Brano")
    }

    @Test("Le indicazioni di versione restano: distinguono due incisioni dello stesso pezzo",
          arguments: [
            "Artista - Brano (Original Mix)",
            "Artista - Brano (Extended Mix)",
            "Artista - Brano (Radio Edit)",
            "Artista - Brano (Tizio Remix)",
            "Artista - Brano (Dub Version)",
            "Artista - Brano (Instrumental)",
          ])
    func keepsVersionMarkers(_ input: String) {
        let parsed = MetadataParser.parse(videoTitle: input, uploader: nil)
        #expect(parsed.artist == "Artista")
        #expect(parsed.title.hasPrefix("Brano ("))
        #expect(parsed.title.hasSuffix(")"))
    }

    @Test("Il prefisso di anteprima dei canali viene tolto")
    func stripsPremierePrefix() {
        let parsed = MetadataParser.parse(
            videoTitle: "PREMIERE: Sansibar - Falling [LSD001]",
            uploader: "Some Blog"
        )
        #expect(parsed.artist == "Sansibar")
        #expect(parsed.title == "Falling")
    }

    @Test("Le quadre finali con etichetta o catalogo spariscono, le tonde con la versione no")
    func dropsTrailingLabelBrackets() {
        let withLabel = MetadataParser.parse(
            videoTitle: "Floating Points - Vocoder [Ninja Tune]", uploader: nil
        )
        #expect(withLabel.title == "Vocoder")

        let withVersion = MetadataParser.parse(
            videoTitle: "Floating Points - Vocoder [Extended Mix]", uploader: nil
        )
        #expect(withVersion.title == "Vocoder [Extended Mix]")
    }

    @Test("Senza separatore l'artista è il canale, ripulito dai suffissi")
    func fallsBackToUploader() {
        let topic = MetadataParser.parse(videoTitle: "Windowlicker", uploader: "Aphex Twin - Topic")
        #expect(topic.artist == "Aphex Twin")
        #expect(topic.title == "Windowlicker")

        let vevo = MetadataParser.parse(videoTitle: "Brano", uploader: "QualcunoVEVO")
        #expect(vevo.artist == "Qualcuno")

        let records = MetadataParser.parse(videoTitle: "Brano", uploader: "Hessle Audio Records")
        #expect(records.artist == "Hessle Audio")
    }

    @Test("Si divide sulla prima occorrenza: il resto appartiene al titolo")
    func splitsOnFirstSeparatorOnly() {
        let parsed = MetadataParser.parse(
            videoTitle: "Artista - Brano - Tizio Remix", uploader: nil
        )
        #expect(parsed.artist == "Artista")
        #expect(parsed.title == "Brano - Tizio Remix")
    }

    @Test("Virgolette e decorazioni ai bordi vengono tolte")
    func trimsDecorations() {
        let parsed = MetadataParser.parse(videoTitle: "Artista - \"Brano\"", uploader: nil)
        #expect(parsed.title == "Brano")
    }

    @Test("Un titolo senza separatore né canale resta intero come titolo")
    func degradesGracefully() {
        let parsed = MetadataParser.parse(videoTitle: "Un titolo qualsiasi", uploader: nil)
        #expect(parsed.artist.isEmpty)
        #expect(parsed.title == "Un titolo qualsiasi")
    }
}

@Suite("Lettura del progresso di yt-dlp")
struct YtDlpProgressTests {

    @Test("La percentuale viene estratta dalle righe di download")
    func parsesProgress() {
        let line = "[download]  42.3% of    4.21MiB at    1.05MiB/s ETA 00:02"
        #expect(YtDlpRunner.progressFraction(from: line) == 0.423)
    }

    @Test("Zero e cento sono compresi negli estremi")
    func parsesBounds() {
        #expect(YtDlpRunner.progressFraction(from: "[download]   0.0% of 4.21MiB") == 0)
        #expect(YtDlpRunner.progressFraction(from: "[download] 100.0% of 4.21MiB") == 1)
    }

    @Test("Le righe che non sono di download vengono ignorate")
    func ignoresOtherLines() {
        #expect(YtDlpRunner.progressFraction(from: "[youtube] Extracting URL: …") == nil)
        #expect(YtDlpRunner.progressFraction(from: "[info] Downloading 1 format(s): 140") == nil)
    }

    @Test("Dallo standard error si prende l'ultima riga utile")
    func picksLastErrorLine() {
        let text = "WARNING: qualcosa\n\nERROR: Video unavailable\n"
        #expect(YtDlpRunner.lastMeaningfulLine(text) == "ERROR: Video unavailable")
    }
}
