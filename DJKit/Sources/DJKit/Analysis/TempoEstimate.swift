import Foundation

/// Il risultato del rilevamento del tempo: i due numeri che finiscono in tabella, più quanto
/// l'analisi ci crede.
public struct TempoEstimate: Hashable, Sendable {
    public let bpm: Double
    /// Posizione del primo downbeat, dentro la prima misura.
    public let beatgridOffsetSeconds: Double
    /// Da 0 a 1: altezza del picco di autocorrelazione scelto, normalizzata.
    ///
    /// Non è una probabilità e non decide niente da sola — un BPM si scrive comunque, perché
    /// correggerlo a mano costa un clic mentre non averlo affatto blocca il quantize. Serve a
    /// segnalare nell'interfaccia i pezzi su cui conviene dare un'occhiata alla griglia.
    public let confidence: Double

    public init(bpm: Double, beatgridOffsetSeconds: Double, confidence: Double) {
        self.bpm = bpm
        self.beatgridOffsetSeconds = beatgridOffsetSeconds
        self.confidence = confidence
    }

    public var beatgrid: Beatgrid? {
        Beatgrid(bpm: bpm, offsetSeconds: beatgridOffsetSeconds)
    }
}
