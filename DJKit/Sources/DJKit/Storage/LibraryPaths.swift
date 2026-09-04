import Foundation

/// Dove vivono i dati dell'utente: database, audio scaricato, cache dei peaks, foto delle
/// etichette e binari sidecar aggiornati.
///
/// Il database contiene solo **nomi di file**, mai percorsi assoluti: la risoluzione passa sempre
/// da qui, così la libreria resta spostabile e i test possono lavorare su una radice temporanea.
public struct LibraryPaths: Sendable, Hashable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// La libreria vera dell'utente: `~/Library/Application Support/Crate/`.
    public static func standard() throws -> LibraryPaths {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return LibraryPaths(root: appSupport.appending(path: "Crate", directoryHint: .isDirectory))
    }

    public var databaseURL: URL { root.appending(path: "library.sqlite") }
    public var audioDirectory: URL { root.appending(path: "Audio", directoryHint: .isDirectory) }
    public var peaksDirectory: URL { root.appending(path: "Peaks", directoryHint: .isDirectory) }
    public var artworkDirectory: URL { root.appending(path: "Artwork", directoryHint: .isDirectory) }
    /// yt-dlp aggiornato dall'app: ha la precedenza su quello incluso nel bundle.
    public var toolsDirectory: URL { root.appending(path: "Tools", directoryHint: .isDirectory) }
    /// Download in corso e conversioni ffmpeg: svuotata all'avvio.
    public var scratchDirectory: URL { root.appending(path: "Scratch", directoryHint: .isDirectory) }

    public var allDirectories: [URL] {
        [root, audioDirectory, peaksDirectory, artworkDirectory, toolsDirectory, scratchDirectory]
    }

    public func createDirectories() throws {
        for directory in allDirectories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public func audioURL(filename: String) -> URL { audioDirectory.appending(path: filename) }
    public func peaksURL(filename: String) -> URL { peaksDirectory.appending(path: filename) }
    public func artworkURL(filename: String) -> URL { artworkDirectory.appending(path: filename) }

    // MARK: - Convenzioni di denominazione

    public func audioFilename(trackID: String, fileExtension: String) -> String {
        "\(trackID).\(fileExtension)"
    }

    public func peaksFilename(trackID: String) -> String { "\(trackID).peaks" }

    public func artworkFilename(trackID: String, side: VinylSide, fileExtension: String) -> String {
        "\(trackID)-\(side.rawValue).\(fileExtension)"
    }

    /// Ripulisce la cartella dei lavori in corso: un download interrotto non deve lasciare rifiuti.
    public func clearScratch() throws {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(
            at: scratchDirectory, includingPropertiesForKeys: nil
        ) else { return }
        for url in contents {
            try? fileManager.removeItem(at: url)
        }
    }
}

/// Lato del disco a cui si riferisce la foto dell'etichetta.
public enum VinylSide: String, Codable, Sendable, CaseIterable {
    case a = "A"
    case b = "B"
}
