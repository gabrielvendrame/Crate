import Foundation
import Testing
@testable import DJKit

@Suite("Riconoscimento dei link YouTube")
struct YouTubeURLTests {

    @Test("Estrae l'id dalle forme di link più comuni",
          arguments: [
            "https://www.youtube.com/watch?v=wqf-xIyf5y4",
            "https://youtube.com/watch?v=wqf-xIyf5y4",
            "https://m.youtube.com/watch?v=wqf-xIyf5y4",
            "https://music.youtube.com/watch?v=wqf-xIyf5y4",
            "https://youtu.be/wqf-xIyf5y4",
            "https://www.youtube.com/shorts/wqf-xIyf5y4",
            "https://www.youtube.com/embed/wqf-xIyf5y4",
            "wqf-xIyf5y4",
          ])
    func extractsIdentifier(_ input: String) {
        #expect(YouTubeURL.videoID(from: input) == "wqf-xIyf5y4")
    }

    @Test("Il parametro di playlist viene ignorato: si importa il brano, non la radio")
    func ignoresPlaylistParameter() {
        let link = "https://www.youtube.com/watch?v=wqf-xIyf5y4&list=RDjLEvbgq2oEQ&index=7"
        #expect(YouTubeURL.videoID(from: link) == "wqf-xIyf5y4")
    }

    @Test("Spazi e a capo attorno al link non danno fastidio")
    func toleratesWhitespace() {
        #expect(YouTubeURL.videoID(from: "  https://youtu.be/wqf-xIyf5y4\n") == "wqf-xIyf5y4")
    }

    @Test("Ciò che non è YouTube viene rifiutato",
          arguments: [
            "https://example.com/watch?v=wqf-xIyf5y4",
            "https://soundcloud.com/qualcosa",
            "non un link",
            "",
            "https://www.youtube.com/",
            "https://www.youtube.com/watch?v=corto",
            "https://www.youtube.com/watch?v=questoedecisamentetroppolungo",
            "https://www.youtube.com/watch?v=id.con.punti",
          ])
    func rejectsEverythingElse(_ input: String) {
        #expect(YouTubeURL.videoID(from: input) == nil)
    }

    @Test("Il link canonico non porta dietro playlist o posizione")
    func buildsCanonicalURL() {
        #expect(
            YouTubeURL.canonicalURL(videoID: "wqf-xIyf5y4")
            == "https://www.youtube.com/watch?v=wqf-xIyf5y4"
        )
    }
}
