import AVFoundation
import Foundation

/// Proprietà di base di un file audio, lette senza decodificarlo per intero.
public struct AudioFileInfo: Sendable, Equatable {
    public let durationSeconds: Double
    public let sampleRate: Double
    public let channelCount: Int
    public let frameCount: Int64

    public static func read(from url: URL) throws -> AudioFileInfo {
        let file = try AVAudioFile(forReading: url)
        let format = file.processingFormat
        return AudioFileInfo(
            durationSeconds: format.sampleRate > 0 ? Double(file.length) / format.sampleRate : 0,
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            frameCount: file.length
        )
    }
}
