import Foundation

/// Riconosce l'identificativo di un video dentro un link YouTube.
///
/// Serve prima di scaricare: con l'id si verifica se il brano è già in libreria, evitando un
/// download inutile di parecchi megabyte.
public enum YouTubeURL {
    /// Gli id di YouTube sono 11 caratteri fra lettere, cifre, trattino e underscore.
    private static let identifierLength = 11

    public static func videoID(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Un id incollato da solo, senza link attorno.
        if isValidIdentifier(trimmed) { return trimmed }

        guard let components = URLComponents(string: trimmed), let host = components.host else {
            return nil
        }
        let bareHost = host.lowercased().replacingOccurrences(of: "www.", with: "")
        guard bareHost.hasSuffix("youtube.com") || bareHost == "youtu.be" else { return nil }

        // youtu.be/ID
        if bareHost == "youtu.be" {
            let candidate = String(components.path.dropFirst())
            return isValidIdentifier(candidate) ? candidate : nil
        }

        // youtube.com/watch?v=ID — anche con &list=… appresso, che ignoriamo.
        if let value = components.queryItems?.first(where: { $0.name == "v" })?.value,
           isValidIdentifier(value) {
            return value
        }

        // youtube.com/shorts/ID, /embed/ID, /live/ID, /v/ID
        let segments = components.path.split(separator: "/").map(String.init)
        if segments.count >= 2,
           ["shorts", "embed", "live", "v"].contains(segments[0]),
           isValidIdentifier(segments[1]) {
            return segments[1]
        }

        return nil
    }

    public static func isValidIdentifier(_ candidate: String) -> Bool {
        guard candidate.count == identifierLength else { return false }
        return candidate.allSatisfy { $0.isLetter && $0.isASCII || $0.isNumber || $0 == "-" || $0 == "_" }
    }

    /// Link canonico, senza parametri di playlist o posizione.
    public static func canonicalURL(videoID: String) -> String {
        "https://www.youtube.com/watch?v=\(videoID)"
    }
}
