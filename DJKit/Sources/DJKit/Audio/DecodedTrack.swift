import Foundation

/// La traccia pronta per il thread audio: un'unica allocazione contigua di `Float`, con i canali
/// uno dopo l'altro e una cornice di zeri agli estremi.
///
/// Non è un `DecodedAudio` in più: `DecodedAudio` è un valore con array Swift, e leggere un array
/// dentro il render callback significa passare per il controllo di unicità di CoW. Qui la memoria
/// è raw, i puntatori sono stabili per tutta la vita dell'oggetto e nessuna lettura può allocare
/// o prendere un lock.
///
/// La **cornice** (`guardFrames` zeri prima del frame 0 e dopo l'ultimo) esiste per far sparire i
/// controlli di bordo dall'interpolazione: Catmull-Rom legge `i-1 … i+2`, e con la cornice quegli
/// indici sono sempre memoria valida anche sul primo e sull'ultimo frame della traccia.
///
/// Costo: gli stessi byte del `DecodedAudio` da cui nasce — 116 MB per un brano di 5:45 a 44,1 kHz
/// stereo — più la cornice, che è irrilevante. Durante la copia i due esistono insieme; il
/// `DecodedAudio` viene rilasciato subito dopo.
public final class DecodedTrack: @unchecked Sendable {
    /// Il grafo audio esce a due canali: un file mono si duplica, uno multicanale si tronca.
    public static let maxChannels = 2
    /// Quattro sample di zeri per lato: due basterebbero per Catmull-Rom, quattro tengono anche
    /// un eventuale arrotondamento del playhead oltre il bordo.
    private static let guardFrames = 4

    public let frameCount: Int
    public let sampleRate: Double
    /// 1 o 2 — vedi `maxChannels`.
    public let channelCount: Int

    private let storage: UnsafeMutablePointer<Float>
    /// Distanza fra l'inizio di un canale e quello del successivo, cornice compresa.
    private let channelStride: Int

    public init(audio: DecodedAudio) {
        frameCount = max(0, audio.frameCount)
        sampleRate = audio.sampleRate
        channelCount = min(max(1, audio.channelCount), Self.maxChannels)
        channelStride = frameCount + 2 * Self.guardFrames

        let total = channelStride * channelCount
        storage = .allocate(capacity: total)
        // Un solo azzeramento iniziale: copre la cornice di entrambi i canali e la coda di un
        // file più corto di quanto dichiarava.
        storage.initialize(repeating: 0, count: total)

        for channel in 0..<channelCount {
            guard channel < audio.channels.count else { break }
            let source = audio.channels[channel]
            let count = min(source.count, frameCount)
            guard count > 0 else { continue }
            let destination = storage.advanced(by: channel * channelStride + Self.guardFrames)
            source.withUnsafeBufferPointer { input in
                destination.update(from: input.baseAddress!, count: count)
            }
        }
    }

    deinit {
        storage.deallocate()
    }

    public var durationSeconds: Double {
        sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }

    /// Puntatore al frame 0 del canale. Leggibile da `-guardFrames` a `frameCount + guardFrames`
    /// escluso: fuori da lì è memoria di qualcun altro.
    public func base(ofChannel channel: Int) -> UnsafePointer<Float> {
        let index = min(max(0, channel), channelCount - 1)
        return UnsafePointer(storage.advanced(by: index * channelStride + Self.guardFrames))
    }

    /// Il sample al frame indicato, o 0 fuori dalla traccia. Comodo nei test; il render callback
    /// lavora sui puntatori.
    public func sample(channel: Int, frame: Int) -> Float {
        guard frame >= -Self.guardFrames, frame < frameCount + Self.guardFrames else { return 0 }
        return base(ofChannel: channel)[frame]
    }
}
