import Foundation

/// Trova i binari sidecar, preferendo la copia aggiornata dall'app a quella inclusa nel bundle.
///
/// yt-dlp invecchia in fretta — YouTube cambia e la versione impacchettata smette di funzionare —
/// quindi il comando "Aggiorna yt-dlp" ne scrive una nuova in `Application Support/Crate/Tools/`
/// e quella ha la precedenza.
public struct ToolLocator: Sendable {
    public enum Tool: String, Sendable, CaseIterable {
        case ytDlp = "yt-dlp"
        case ffmpeg = "ffmpeg"

        /// Posizioni possibili dentro una cartella di strumenti, in ordine di preferenza.
        ///
        /// yt-dlp viene distribuito sia come cartella "onedir" sia come binario singolo. La
        /// onedir è quella che impacchettiamo, perché il binario singolo si riespande in una
        /// cartella temporanea a ogni lancio e macOS lo riscansiona ogni volta: ~13 secondi di
        /// avvio contro ~0,4. Il binario singolo resta accettato come ripiego.
        var relativePaths: [String] {
            switch self {
            case .ytDlp: ["yt-dlp/yt-dlp_macos", "yt-dlp"]
            case .ffmpeg: ["ffmpeg"]
            }
        }
    }

    private let updatedDirectory: URL?
    private let bundledDirectory: URL?

    public init(paths: LibraryPaths?, bundle: Bundle = .main) {
        self.updatedDirectory = paths?.toolsDirectory
        self.bundledDirectory = bundle.resourceURL?.appending(
            path: "Tools", directoryHint: .isDirectory
        )
    }

    /// Inizializzatore esplicito per i test, dove `Bundle.main` è quello del test runner.
    public init(updatedDirectory: URL?, bundledDirectory: URL?) {
        self.updatedDirectory = updatedDirectory
        self.bundledDirectory = bundledDirectory
    }

    public func url(for tool: Tool) -> URL? {
        for directory in [updatedDirectory, bundledDirectory].compactMap(\.self) {
            for relativePath in tool.relativePaths {
                let candidate = directory.appending(path: relativePath)
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }

    public func require(_ tool: Tool) throws -> URL {
        guard let url = url(for: tool) else {
            throw ToolLocatorError.missing(tool)
        }
        return url
    }
}

public enum ToolLocatorError: LocalizedError {
    case missing(ToolLocator.Tool)

    public var errorDescription: String? {
        switch self {
        case .missing(let tool):
            "Binario \(tool.rawValue) non trovato. Esegui ./Scripts/fetch-tools.sh e ricompila."
        }
    }
}
