import Foundation

/// Come si costruisce la ricerca su Discogs partendo dai metadati di una traccia.
///
/// Sta a parte dal client perché è **logica pura e piena di casi storti**: i titoli che arrivano da
/// YouTube portano dietro remix, edit, etichette fra parentesi e a volte l'artista ripetuto. Qui si
/// prova con `swift test`, senza toccare la rete.
///
/// La ricerca è a **tentativi in ordine di precisione**: si parte dalla domanda più stretta e si
/// allarga solo se non torna niente. Cercare subito largo darebbe dieci dischi diversi da scegliere
/// anche quando ce n'è uno solo che è quello giusto.
public enum DiscogsQuery {
    /// Un tentativo: i parametri da mandare e se vale la pena allargare dopo.
    public struct Attempt: Equatable, Sendable {
        public let parameters: [String: String]
        /// Solo edizioni in vinile. Il primo tentativo lo è sempre: è un'app per set in vinile, e
        /// l'etichetta che si vuole fotografare è quella del disco.
        public let vinylOnly: Bool
    }

    public static func attempts(artist: String, title: String) -> [Attempt] {
        let cleanArtist = clean(artist)
        let cleanTitle = clean(title)
        let bareTitle = removingParentheticals(from: cleanTitle)

        var attempts: [Attempt] = []

        if !cleanArtist.isEmpty, !cleanTitle.isEmpty {
            // `track=` cerca fra i brani dei dischi, che è la domanda giusta: di un pezzo si
            // conosce il titolo, non l'album da cui viene.
            attempts.append(Attempt(
                parameters: ["artist": cleanArtist, "track": cleanTitle], vinylOnly: true
            ))
            if bareTitle != cleanTitle, !bareTitle.isEmpty {
                attempts.append(Attempt(
                    parameters: ["artist": cleanArtist, "track": bareTitle], vinylOnly: true
                ))
            }
            attempts.append(Attempt(
                parameters: ["artist": cleanArtist, "track": bareTitle.isEmpty ? cleanTitle : bareTitle],
                vinylOnly: false
            ))
        }

        let free = [cleanArtist, bareTitle.isEmpty ? cleanTitle : bareTitle]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !free.isEmpty {
            attempts.append(Attempt(parameters: ["q": free], vinylOnly: true))
            attempts.append(Attempt(parameters: ["q": free], vinylOnly: false))
        }

        return attempts
    }

    public static func attempts(for track: Track) -> [Attempt] {
        attempts(artist: track.artist, title: track.title)
    }

    /// Toglie il rumore che Discogs non capisce e che restringe la ricerca a zero risultati.
    ///
    /// Non tocca invece le parentesi: "(Matt Schrewd Mix)" è un remix vero e su Discogs esiste con
    /// quel nome. Sono i tentativi successivi a provare senza.
    static func clean(_ value: String) -> String {
        var text = value
        for noise in ["official video", "official audio", "hq", "hd", "free download"] {
            text = text.replacingOccurrences(
                of: noise, with: "", options: [.caseInsensitive]
            )
        }
        // I caratteri che Discogs tratta come operatori o che spezzano la ricerca.
        text = text.replacingOccurrences(of: "\"", with: " ")
        text = text.components(separatedBy: CharacterSet(charactersIn: "|/\\")).joined(separator: " ")
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// Il titolo senza le parentesi finali: "What's A Girl To Do (Done031)" → "What's A Girl To Do".
    static func removingParentheticals(from value: String) -> String {
        var text = value
        for pattern in ["\\([^)]*\\)", "\\[[^\\]]*\\]"] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}
