import Foundation

/// Un intervallo di sample riassunto in cinque numeri: due per la sagoma, tre per il colore.
public struct PeakBin: Sendable, Equatable {
    /// Ampiezza minima e massima nell'intervallo, in −1…1. Danno l'altezza della colonna.
    public var minimum: Float
    public var maximum: Float
    /// Livello RMS nelle tre bande, 0…1: **low** < 200 Hz, **mid** 200 Hz–4 kHz, **high** > 4 kHz.
    /// Il loro rapporto dà il colore della colonna, come in rekordbox.
    public var low: Float
    public var mid: Float
    public var high: Float

    public init(minimum: Float, maximum: Float, low: Float, mid: Float, high: Float) {
        self.minimum = minimum
        self.maximum = maximum
        self.low = low
        self.mid = mid
        self.high = high
    }

    public static let silent = PeakBin(minimum: 0, maximum: 0, low: 0, mid: 0, high: 0)

    /// Escursione massima dallo zero: quanto è alta la colonna se la si disegna simmetrica.
    public var amplitude: Float { max(-minimum, maximum) }
}
