import Foundation

/// Un livello di zoom della cache: la traccia intera riassunta con bin di `binSize` sample.
public struct PeaksLevel: Sendable {
    /// Quanti sample confluiscono in un bin (64, 256, 1024 o 4096).
    public let binSize: Int
    public let bins: [PeakBin]

    public init(binSize: Int, bins: [PeakBin]) {
        self.binSize = binSize
        self.bins = bins
    }

    public var count: Int { bins.count }

    /// Il bin che contiene un dato frame, o `nil` fuori dalla traccia.
    public func bin(atFrame frame: Int) -> PeakBin? {
        let index = frame / binSize
        guard bins.indices.contains(index) else { return nil }
        return bins[index]
    }
}
