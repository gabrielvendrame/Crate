import Foundation

public enum ToolsUpdateError: LocalizedError {
    case releaseUnavailable(String)
    case assetNotFound
    case unpackFailed(String)
    case executableMissing

    public var errorDescription: String? {
        switch self {
        case .releaseUnavailable(let detail):
            "Non riesco a leggere l'ultima versione di yt-dlp: \(detail)"
        case .assetNotFound:
            "L'ultima release di yt-dlp non contiene il pacchetto per macOS."
        case .unpackFailed(let detail):
            "Il pacchetto scaricato non si è aperto: \(detail)"
        case .executableMissing:
            "Nel pacchetto scaricato non c'è l'eseguibile atteso."
        }
    }
}

public struct ToolsUpdateResult: Sendable, Equatable {
    public let version: String
    public let installedAt: URL
}

/// Scarica l'ultima release di yt-dlp e la installa in `Application Support/Crate/Tools/`, dove
/// `ToolLocator` la trova prima di quella inclusa nel bundle.
///
/// **Si scarica la variante "onedir" (`yt-dlp_macos.zip`), mai il binario singolo**, per lo stesso
/// motivo per cui è quella impacchettata: il file singolo è un PyInstaller *onefile* che si
/// riespande in una cartella temporanea a ogni lancio, e macOS ne riscansiona il contenuto ogni
/// volta — 13 secondi di avvio per invocazione contro 0,33. Un aggiornamento che "semplifica"
/// prendendo il binario singolo renderebbe l'app lenta senza rompere niente di visibile.
///
/// L'installazione è **atomica dal punto di vista di chi usa l'app**: si spacchetta di fianco e si
/// scambia la cartella alla fine, così un download interrotto non lascia un yt-dlp mezzo scritto
/// che poi non parte.
public struct ToolsUpdater: Sendable {
    /// La release più recente, secondo l'API di GitHub.
    static let releaseAPI = URL(string: "https://api.github.com/repos/yt-dlp/yt-dlp/releases/latest")!
    /// Il nome dell'asset da prendere: la cartella onedir per macOS.
    static let assetName = "yt-dlp_macos.zip"
    /// Dove sta l'eseguibile dentro il pacchetto, e come si chiama la cartella installata.
    static let installedDirectoryName = "yt-dlp"
    static let executableName = "yt-dlp_macos"

    private let paths: LibraryPaths
    private let session: URLSession

    public init(paths: LibraryPaths, session: URLSession = .shared) {
        self.paths = paths
        self.session = session
    }

    @discardableResult
    public func update(
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> ToolsUpdateResult {
        let release = try await latestRelease()
        onProgress?(0.1)

        let archive = try await download(release.assetURL, onProgress: {
            onProgress?(0.1 + $0 * 0.7)
        })
        defer { try? FileManager.default.removeItem(at: archive.deletingLastPathComponent()) }

        let installed = try await install(archive: archive)
        onProgress?(1)
        return ToolsUpdateResult(version: release.version, installedAt: installed)
    }

    /// La versione installata adesso, chiedendola al binario stesso. `nil` se non c'è o non parte.
    public static func installedVersion(locator: ToolLocator) async -> String? {
        guard let url = locator.url(for: .ytDlp) else { return nil }
        guard let result = try? await ProcessRunner.run(executable: url, arguments: ["--version"]),
              result.didSucceed
        else { return nil }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    // MARK: - Passaggi

    struct Release: Sendable {
        let version: String
        let assetURL: URL
    }

    func latestRelease() async throws -> Release {
        var request = URLRequest(url: Self.releaseAPI)
        // GitHub rifiuta le richieste senza User-Agent, e senza `Accept` restituisce una forma
        // che potrebbe cambiare.
        request.setValue("Crate", forHTTPHeaderField: "User-Agent")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw ToolsUpdateError.releaseUnavailable(error.localizedDescription)
        }
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ToolsUpdateError.releaseUnavailable("GitHub ha risposto \(http.statusCode)")
        }

        struct Payload: Decodable {
            struct Asset: Decodable {
                let name: String
                let browserDownloadURL: URL

                enum CodingKeys: String, CodingKey {
                    case name
                    case browserDownloadURL = "browser_download_url"
                }
            }
            let tagName: String
            let assets: [Asset]

            enum CodingKeys: String, CodingKey {
                case tagName = "tag_name"
                case assets
            }
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw ToolsUpdateError.releaseUnavailable("risposta non riconosciuta")
        }
        guard let asset = payload.assets.first(where: { $0.name == Self.assetName }) else {
            throw ToolsUpdateError.assetNotFound
        }
        return Release(version: payload.tagName, assetURL: asset.browserDownloadURL)
    }

    /// Scarica in una cartella di lavoro dentro `Scratch/`, che viene svuotata a ogni avvio.
    private func download(
        _ url: URL,
        onProgress: (@Sendable (Double) -> Void)?
    ) async throws -> URL {
        let workingDirectory = paths.scratchDirectory
            .appending(path: "tools-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let destination = workingDirectory.appending(path: Self.assetName)

        var request = URLRequest(url: url)
        request.setValue("Crate", forHTTPHeaderField: "User-Agent")

        let (bytes, response) = try await session.bytes(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            throw ToolsUpdateError.releaseUnavailable("il download ha risposto \(http.statusCode)")
        }
        let expected = response.expectedContentLength

        // Si scrive a blocchi invece di tenere i 124 MB in memoria, e per lo stesso giro si ha il
        // progresso: senza, l'unica alternativa sarebbe una barra indeterminata su un minuto di
        // attesa.
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let handle = try FileHandle(forWritingTo: destination)
        defer { try? handle.close() }

        var buffer = Data()
        buffer.reserveCapacity(1 << 20)
        var written: Int64 = 0
        for try await byte in bytes {
            buffer.append(byte)
            if buffer.count >= 1 << 20 {
                try handle.write(contentsOf: buffer)
                written += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                if expected > 0 { onProgress?(min(1, Double(written) / Double(expected))) }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
        }
        onProgress?(1)
        return destination
    }

    /// Spacchetta e scambia la cartella installata.
    func install(archive: URL) async throws -> URL {
        let staging = archive.deletingLastPathComponent()
            .appending(path: "unpacked", directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)

        // `ditto -x -k` invece di `unzip`: è lo strumento di sistema per gli archivi zip di
        // macOS e conserva i permessi di esecuzione, che è esattamente ciò che serve qui.
        let result = try await ProcessRunner.run(
            executable: URL(filePath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", archive.path, staging.path]
        )
        guard result.didSucceed else {
            let detail = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw ToolsUpdateError.unpackFailed(
                detail.isEmpty ? "ditto ha risposto \(result.terminationStatus)" : detail
            )
        }

        guard let unpacked = try locateUnpackedDirectory(in: staging) else {
            throw ToolsUpdateError.executableMissing
        }

        let destination = paths.toolsDirectory.appending(
            path: Self.installedDirectoryName, directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: paths.toolsDirectory, withIntermediateDirectories: true
        )
        // Lo scambio è l'ultimo gesto: fino a qui la copia in uso resta quella di prima.
        let previous = destination.appendingPathExtension("previous")
        try? FileManager.default.removeItem(at: previous)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: destination, to: previous)
        }
        do {
            try FileManager.default.moveItem(at: unpacked, to: destination)
        } catch {
            // Rimettere a posto la vecchia è meglio che restare senza yt-dlp.
            try? FileManager.default.moveItem(at: previous, to: destination)
            throw ToolsUpdateError.unpackFailed(error.localizedDescription)
        }
        try? FileManager.default.removeItem(at: previous)

        let executable = destination.appending(path: Self.executableName)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw ToolsUpdateError.executableMissing
        }
        return destination
    }

    /// La cartella che contiene l'eseguibile, dentro l'archivio spacchettato.
    ///
    /// Lo zip di yt-dlp contiene una cartella `yt-dlp_macos/` con dentro l'eseguibile e
    /// `_internal/`, ma il livello è cambiato fra le versioni: si cerca l'eseguibile invece di
    /// dare per scontata la forma dell'archivio.
    private func locateUnpackedDirectory(in staging: URL) throws -> URL? {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: staging.appending(path: Self.executableName).path) {
            return staging
        }
        let contents = try fileManager.contentsOfDirectory(
            at: staging, includingPropertiesForKeys: [.isDirectoryKey]
        )
        for url in contents {
            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
            guard isDirectory == true else { continue }
            if fileManager.fileExists(atPath: url.appending(path: Self.executableName).path) {
                return url
            }
        }
        return nil
    }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
