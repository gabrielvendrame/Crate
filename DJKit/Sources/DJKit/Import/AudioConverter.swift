import AVFoundation
import Foundation

public enum AudioConverterError: LocalizedError {
    case conversionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .conversionFailed(let detail):
            "Conversione audio fallita: \(detail)"
        }
    }
}

/// Porta in un contenitore leggibile i file che AVFoundation non apre.
///
/// Succede quando YouTube serve solo Opus in WebM. La conversione va in **ALAC**, che è lossless:
/// ricomprimere in un formato con perdita sommerebbe una seconda degradazione a quella già subita
/// dalla sorgente.
public struct AudioConverter: Sendable {
    private let locator: ToolLocator

    public init(locator: ToolLocator) {
        self.locator = locator
    }

    /// Prova ad aprire il file: è la stessa domanda che si porrà il deck al caricamento, quindi la
    /// risposta più affidabile è provarci davvero invece di indovinare dall'estensione.
    public static func isNativelyDecodable(_ url: URL) -> Bool {
        (try? AVAudioFile(forReading: url)) != nil
    }

    public func convertToALAC(source: URL, destination: URL) async throws -> URL {
        let ffmpeg = try locator.require(.ffmpeg)
        let result = try await ProcessRunner.run(
            executable: ffmpeg,
            arguments: [
                "-nostdin",
                "-loglevel", "error",
                "-y",
                "-i", source.path,
                "-vn",                  // scarta l'eventuale copertina incorporata
                "-c:a", "alac",
                destination.path,
            ]
        )
        guard result.didSucceed else {
            throw AudioConverterError.conversionFailed(
                YtDlpRunner.lastMeaningfulLine(result.standardError)
            )
        }
        return destination
    }
}
