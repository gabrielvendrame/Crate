import Foundation

/// Ciò che sappiamo di un video prima di scaricarlo.
public struct VideoInfo: Sendable, Equatable {
    public var id: String
    public var title: String
    public var uploader: String?
    public var durationSeconds: Double
    public var webpageURL: String

    public init(
        id: String,
        title: String,
        uploader: String?,
        durationSeconds: Double,
        webpageURL: String
    ) {
        self.id = id
        self.title = title
        self.uploader = uploader
        self.durationSeconds = durationSeconds
        self.webpageURL = webpageURL
    }
}

public enum YtDlpError: LocalizedError {
    case interrogationFailed(String)
    case downloadFailed(String)
    case unreadableInfo
    case fileNotProduced

    public var errorDescription: String? {
        switch self {
        case .interrogationFailed(let detail):
            "yt-dlp non è riuscito a leggere il video: \(detail)"
        case .downloadFailed(let detail):
            "Download fallito: \(detail)"
        case .unreadableInfo:
            "yt-dlp ha risposto in un formato inatteso."
        case .fileNotProduced:
            "Il download si è concluso ma non ha prodotto alcun file audio."
        }
    }
}

/// Interroga e scarica da YouTube tramite il binario yt-dlp.
public actor YtDlpRunner {
    private let locator: ToolLocator

    public init(locator: ToolLocator) {
        self.locator = locator
    }

    /// Argomenti comuni a ogni invocazione.
    ///
    /// `--no-playlist` è essenziale: i link copiati da YouTube portano spesso dietro un
    /// `&list=RD…` (il mix automatico), e senza questo yt-dlp scaricherebbe l'intera radio invece
    /// del brano voluto.
    private var commonArguments: [String] {
        ["--no-playlist", "--no-warnings", "--ignore-config"]
    }

    public func fetchInfo(url: String) async throws -> VideoInfo {
        let executable = try locator.require(.ytDlp)
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: commonArguments + ["--dump-single-json", url]
        )

        guard result.didSucceed else {
            throw YtDlpError.interrogationFailed(Self.lastMeaningfulLine(result.standardError))
        }
        guard let data = result.standardOutput.data(using: .utf8),
              let payload = try? JSONDecoder().decode(InfoPayload.self, from: data)
        else {
            throw YtDlpError.unreadableInfo
        }

        return VideoInfo(
            id: payload.id,
            title: payload.title ?? "",
            uploader: payload.uploader ?? payload.channel ?? payload.uploaderID,
            durationSeconds: payload.duration ?? 0,
            webpageURL: payload.webpageURL ?? url
        )
    }

    /// Scarica la traccia audio nella cartella indicata e restituisce il file prodotto.
    ///
    /// Preferisce l'm4a che YouTube già serve (AAC, formato 140): AVFoundation lo apre
    /// nativamente, quindi non serve alcuna ricodifica. Solo se il video ha esclusivamente Opus in
    /// contenitore WebM il file andrà convertito a valle, da `AudioConverter`.
    public func downloadAudio(
        url: String,
        into directory: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> URL {
        let executable = try locator.require(.ytDlp)
        let template = directory.appending(path: "%(id)s.%(ext)s").path

        var arguments = commonArguments + [
            "--newline",                                  // progresso su righe separate
            "--no-part",                                  // niente file .part da ripulire
            "-f", "bestaudio[ext=m4a]/bestaudio",
            "-o", template,
        ]
        if let ffmpeg = locator.url(for: .ffmpeg) {
            arguments += ["--ffmpeg-location", ffmpeg.deletingLastPathComponent().path]
        }
        arguments.append(url)

        let before = Self.contents(of: directory)
        let result = try await ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            onOutputLine: { line in
                if let fraction = Self.progressFraction(from: line) {
                    onProgress?(fraction)
                }
            }
        )

        guard result.didSucceed else {
            throw YtDlpError.downloadFailed(Self.lastMeaningfulLine(result.standardError))
        }

        let after = Self.contents(of: directory)
        guard let produced = after.subtracting(before).first.map({ directory.appending(path: $0) })
            ?? after.first.map({ directory.appending(path: $0) })
        else {
            throw YtDlpError.fileNotProduced
        }
        return produced
    }

    public func version() async throws -> String {
        let executable = try locator.require(.ytDlp)
        let result = try await ProcessRunner.run(executable: executable, arguments: ["--version"])
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Utilità

    private static func contents(of directory: URL) -> Set<String> {
        Set((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
    }

    /// Estrae la percentuale da una riga tipo `[download]  42.3% of 4.21MiB at …`.
    static func progressFraction(from line: String) -> Double? {
        guard line.hasPrefix("[download]"),
              let percentRange = line.range(of: "%")
        else { return nil }

        let beforePercent = line[..<percentRange.lowerBound]
        let digits = beforePercent.reversed().prefix { $0.isNumber || $0 == "." }
        guard let value = Double(String(digits.reversed())) else { return nil }
        return min(max(value / 100, 0), 1)
    }

    /// L'ultima riga non vuota dello standard error: yt-dlp mette lì il motivo del fallimento.
    static func lastMeaningfulLine(_ text: String) -> String {
        let lines = text
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.last ?? "nessun dettaglio disponibile"
    }
}

/// Solo i campi che ci servono dal JSON di yt-dlp, che ne contiene centinaia.
private struct InfoPayload: Decodable {
    let id: String
    let title: String?
    let uploader: String?
    let channel: String?
    let uploaderID: String?
    let duration: Double?
    let webpageURL: String?

    enum CodingKeys: String, CodingKey {
        case id, title, uploader, channel, duration
        case uploaderID = "uploader_id"
        case webpageURL = "webpage_url"
    }
}
