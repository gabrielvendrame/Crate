import AVFoundation
import Foundation

public enum AudioDecoderError: LocalizedError {
    case cannotOpen(String)
    case emptyFile
    case unexpectedFormat

    public var errorDescription: String? {
        switch self {
        case .cannotOpen(let detail):
            "Impossibile aprire l'audio: \(detail)"
        case .emptyFile:
            "Il file audio è vuoto."
        case .unexpectedFormat:
            "Formato di decodifica inatteso: serve float32 non interleaved."
        }
    }
}

/// Decodifica un file audio per intero in RAM.
///
/// Legge nel `processingFormat` di `AVAudioFile`, che per qualsiasi sorgente compressa è già
/// float32 non interleaved alla frequenza nativa del file: nessun resampling qui, quello è un
/// problema del deck (M4) che deve adattarsi al device di uscita.
public enum AudioDecoder {
    /// Blocchi da 64k frame, ~1,5 s a 44,1 kHz: abbastanza grandi da rendere trascurabile il
    /// costo per chiamata, abbastanza piccoli da dare un progresso fluido.
    private static let chunkFrames: AVAudioFrameCount = 65_536

    public static func decode(
        url: URL,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) throws -> DecodedAudio {
        let file: AVAudioFile
        do {
            file = try AVAudioFile(forReading: url)
        } catch {
            throw AudioDecoderError.cannotOpen(error.localizedDescription)
        }

        let format = file.processingFormat
        guard format.commonFormat == .pcmFormatFloat32, !format.isInterleaved else {
            throw AudioDecoderError.unexpectedFormat
        }

        let frameCount = Int(file.length)
        guard frameCount > 0 else { throw AudioDecoderError.emptyFile }
        let channelCount = Int(format.channelCount)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw AudioDecoderError.unexpectedFormat
        }

        var channels = [[Float]](
            repeating: [Float](repeating: 0, count: frameCount),
            count: channelCount
        )

        var written = 0
        while written < frameCount {
            try file.read(into: buffer)
            let read = min(Int(buffer.frameLength), frameCount - written)
            guard read > 0, let source = buffer.floatChannelData else { break }

            for channel in 0..<channelCount {
                channels[channel].withUnsafeMutableBufferPointer { destination in
                    destination.baseAddress!
                        .advanced(by: written)
                        .update(from: source[channel], count: read)
                }
            }
            written += read
            onProgress?(Double(written) / Double(frameCount))
        }

        // Un file troncato a metà lettura non è un errore: si tiene ciò che si è letto davvero.
        if written < frameCount {
            for channel in 0..<channelCount {
                channels[channel].removeLast(frameCount - written)
            }
        }

        return DecodedAudio(
            channels: channels,
            sampleRate: format.sampleRate,
            frameCount: written
        )
    }
}
