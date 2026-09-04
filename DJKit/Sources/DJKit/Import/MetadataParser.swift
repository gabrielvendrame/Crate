import Foundation

public struct ParsedMetadata: Sendable, Equatable {
    public var artist: String
    public var title: String

    public init(artist: String, title: String) {
        self.artist = artist
        self.title = title
    }
}

/// Ricava artista e titolo dal titolo di un video YouTube.
///
/// È un'euristica e sbaglierà: il risultato è un punto di partenza che Gabriel corregge
/// nell'ispettore. Il criterio guida è **non buttare via informazione utile a un DJ**: le
/// indicazioni di mix, remix, edit, versione, dub e simili restano nel titolo, perché distinguono
/// due incisioni dello stesso pezzo. Sparisce invece il rumore da YouTube — "Official Video",
/// "HD", "Free Download" — che non dice nulla sul disco.
public enum MetadataParser {

    public static func parse(videoTitle: String, uploader: String? = nil) -> ParsedMetadata {
        var text = stripPremierePrefix(videoTitle)
        text = removeNoiseGroups(from: text)
        text = removeTrailingLabelBrackets(from: text)
        text = normalizeWhitespace(text)

        if let (left, right) = splitOnSeparator(text) {
            let artist = trimDecorations(left)
            let title = trimDecorations(right)
            if !artist.isEmpty, !title.isEmpty {
                return ParsedMetadata(artist: artist, title: title)
            }
        }

        return ParsedMetadata(
            artist: cleanUploader(uploader),
            title: trimDecorations(text)
        )
    }

    // MARK: - Pulizia

    /// I canali che pubblicano in anteprima antepongono "PREMIERE:" o "Etichetta Premiere:".
    private static func stripPremierePrefix(_ text: String) -> String {
        guard let regex = try? Regex("(?i)^[^:]{0,40}\\b(premiere|premiera|first listen)\\b[^:]{0,15}:\\s*")
        else { return text }
        if let match = try? regex.firstMatch(in: text), match.range.lowerBound == text.startIndex {
            return String(text[match.range.upperBound...])
        }
        return text
    }

    /// Elimina i gruppi fra parentesi tonde o quadre il cui contenuto è solo rumore.
    private static func removeNoiseGroups(from text: String) -> String {
        var result = ""
        var group = ""
        var depth = 0
        var openingCharacter: Character = "("

        for character in text {
            if character == "(" || character == "[" {
                if depth == 0 {
                    openingCharacter = character
                    group = ""
                } else {
                    group.append(character)
                }
                depth += 1
            } else if character == ")" || character == "]" {
                depth -= 1
                if depth == 0 {
                    if !isNoise(group) {
                        let closing: Character = openingCharacter == "(" ? ")" : "]"
                        result.append(openingCharacter)
                        result += group
                        result.append(closing)
                    }
                } else if depth > 0 {
                    group.append(character)
                } else {
                    // Parentesi chiusa senza apertura: la teniamo com'è.
                    depth = 0
                    result.append(character)
                }
            } else if depth > 0 {
                group.append(character)
            } else {
                result.append(character)
            }
        }

        // Gruppo mai chiuso: recuperiamo il testo perso.
        if depth > 0 {
            result.append(openingCharacter)
            result += group
        }
        return result
    }

    /// Le quadre finali su YouTube portano quasi sempre etichetta, catalogo o qualità, non titolo.
    /// Le tonde invece portano spesso la versione, quindi restano.
    private static func removeTrailingLabelBrackets(from text: String) -> String {
        var result = normalizeWhitespace(text)
        while result.hasSuffix("]"), let start = result.lastIndex(of: "[") {
            let content = String(result[result.index(after: start)..<result.index(before: result.endIndex)])
            guard !containsMeaningfulKeyword(content) else { break }
            result = normalizeWhitespace(String(result[..<start]))
        }
        return result
    }

    private static let meaningfulKeywords = [
        "mix", "remix", "edit", "version", "dub", "vip", "bootleg", "rework",
        "extended", "radio", "instrumental", "live", "feat", "ft.", "acapella",
        "club", "cover", "reprise", "interlude", "part", "pt."
    ]

    private static func containsMeaningfulKeyword(_ content: String) -> Bool {
        let lowered = content.lowercased()
        return meaningfulKeywords.contains { lowered.contains($0) }
    }

    private static func isNoise(_ content: String) -> Bool {
        let lowered = content
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return true }
        // Un'indicazione di versione vale più del rumore che potrebbe accompagnarla.
        guard !containsMeaningfulKeyword(lowered) else { return false }

        let pattern = """
            (?i)^\\s*(\
            (official\\s*)?(music\\s*|lyrics?\\s*)?(video|audio|visuali[sz]er)|\
            official|lyrics?|lyric\\s*video|m/?v|\
            hd|hq|uhd|4k|8k|full\\s*hd|high\\s*quality|best\\s*quality|audio\\s*only|\
            full\\s*album|album|full|\
            remaster(ed)?(\\s*\\d{4})?|\\d{4}\\s*remaster|\
            free\\s*download|download|out\\s*now|buy|stream|link\\s*in\\s*description|\
            new|explicit|clean|\
            \\d{4}\
            )\\s*$
            """
        guard let regex = try? Regex(pattern) else { return false }
        return (try? regex.firstMatch(in: lowered)) != nil
    }

    // MARK: - Separazione artista / titolo

    private static let separators = [" - ", " – ", " — ", " | ", " • ", " · ", " ~ ", " _ "]

    /// Divide sulla **prima** occorrenza: in "Artista - Titolo - Remix" il remix appartiene al
    /// titolo, non è un terzo campo.
    private static func splitOnSeparator(_ text: String) -> (String, String)? {
        var best: Range<String.Index>?
        for separator in separators {
            if let range = text.range(of: separator) {
                if best == nil || range.lowerBound < best!.lowerBound {
                    best = range
                }
            }
        }
        guard let range = best else { return nil }
        return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
    }

    private static let uploaderSuffixes = [
        "- topic", "vevo", "official", "officiel", "records", "recordings",
        "music", "musique", "tv", "channel", "hd", "label", "media"
    ]

    /// Senza separatore nel titolo, l'artista più plausibile è il canale — ripulito dai suffissi
    /// che i canali si portano dietro. I canali "- Topic" generati da YouTube sono il caso in cui
    /// questo funziona meglio: lì il nome del canale *è* l'artista.
    private static func cleanUploader(_ uploader: String?) -> String {
        guard var name = uploader?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else {
            return ""
        }
        var changed = true
        while changed {
            changed = false
            let lowered = name.lowercased()
            for suffix in uploaderSuffixes where lowered.hasSuffix(suffix) {
                let cut = name.index(name.endIndex, offsetBy: -suffix.count)
                let trimmed = String(name[..<cut]).trimmingCharacters(in: .whitespacesAndNewlines)
                // Non svuotiamo il campo: un canale che si chiama solo "Music" resta "Music".
                if !trimmed.isEmpty {
                    name = trimDecorations(trimmed)
                    changed = true
                    break
                }
            }
        }
        return name
    }

    // MARK: - Utilità

    private static func normalizeWhitespace(_ text: String) -> String {
        text.split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static let decorations = CharacterSet(charactersIn: " \t\n-–—|·•~_\"'“”«»")

    private static func trimDecorations(_ text: String) -> String {
        normalizeWhitespace(text).trimmingCharacters(in: decorations)
    }
}
