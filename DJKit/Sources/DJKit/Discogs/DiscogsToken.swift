import Foundation

/// Dove sta il token personale di Discogs.
///
/// **Un file con permessi 0600 dentro la libreria, non il portachiavi.** Il portachiavi sarebbe il
/// posto giusto in generale, ma questa app è firmata ad hoc e la firma cambia a ogni
/// ricompilazione: l'accesso all'elemento è legato all'identità di firma, quindi ogni build
/// aprirebbe una richiesta di autorizzazione. Un token di Discogs è di sola lettura su un
/// catalogo pubblico e si revoca dal profilo in un clic, quindi il file leggibile solo
/// dall'utente è la scelta proporzionata — e si cancella sapendo dov'è.
public struct DiscogsToken: Sendable {
    private let url: URL

    public init(paths: LibraryPaths) {
        self.url = paths.root.appending(path: "discogs-token")
    }

    public func read() -> String? {
        guard let raw = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    public func write(_ token: String) throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            try remove()
            return
        }
        try Data(trimmed.utf8).write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path
        )
    }

    public func remove() throws {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
