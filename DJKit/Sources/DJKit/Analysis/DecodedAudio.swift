import Accelerate
import Foundation

/// Una traccia decodificata per intero in memoria: un array di `Float` per canale, **non**
/// interleaved.
///
/// È già il layout che servirà al deck in M4 — il render callback legge da qui senza conversioni —
/// quindi il decoder produce direttamente la forma definitiva invece di una intermedia.
/// Costo misurato: 116 MB per un brano di 5:45 a 44,1 kHz stereo.
public struct DecodedAudio: Sendable {
    /// Un elemento per canale, tutti della stessa lunghezza (`frameCount`).
    public let channels: [[Float]]
    public let sampleRate: Double
    public let frameCount: Int

    public init(channels: [[Float]], sampleRate: Double, frameCount: Int) {
        self.channels = channels
        self.sampleRate = sampleRate
        self.frameCount = frameCount
    }

    public var channelCount: Int { channels.count }

    public var durationSeconds: Double {
        sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }

    /// Somma dei canali divisa per il loro numero.
    ///
    /// Peaks e rilevamento del tempo lavorano entrambi sul mono: la waveform di un deck è una sola
    /// e le differenze fra i canali non aggiungono nulla a ciò che serve vedere o misurare.
    public func makeMono() -> [Float] {
        guard let first = channels.first else { return [] }
        guard channels.count > 1 else { return first }

        var mono = [Float](repeating: 0, count: frameCount)
        mono.withUnsafeMutableBufferPointer { output in
            guard let out = output.baseAddress else { return }
            for channel in channels where channel.count >= frameCount {
                channel.withUnsafeBufferPointer { input in
                    vDSP_vadd(out, 1, input.baseAddress!, 1, out, 1, vDSP_Length(frameCount))
                }
            }
            var scale = 1 / Float(channels.count)
            vDSP_vsmul(out, 1, &scale, out, 1, vDSP_Length(frameCount))
        }
        return mono
    }
}
