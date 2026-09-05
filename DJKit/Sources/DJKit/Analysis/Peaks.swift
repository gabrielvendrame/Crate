import Foundation

/// La cache della waveform di una traccia: gli stessi campioni riassunti a quattro risoluzioni.
///
/// Overview dell'intero brano e vista zoomata leggono dalla stessa struttura, ognuna dal livello
/// che le serve, senza mai ricalcolare nulla a schermo.
public struct Peaks: Sendable {
    public let sampleRate: Double
    public let frameCount: Int
    public let channelCount: Int
    /// Ordinati dal bin più piccolo al più grande.
    public let levels: [PeaksLevel]

    public init(sampleRate: Double, frameCount: Int, channelCount: Int, levels: [PeaksLevel]) {
        self.sampleRate = sampleRate
        self.frameCount = frameCount
        self.channelCount = channelCount
        self.levels = levels.sorted { $0.binSize < $1.binSize }
    }

    public var durationSeconds: Double {
        sampleRate > 0 ? Double(frameCount) / sampleRate : 0
    }

    public func level(binSize: Int) -> PeaksLevel? {
        levels.first { $0.binSize == binSize }
    }

    /// Il livello adatto a una data scala di disegno: il bin più grande che ne lascia comunque
    /// almeno uno per pixel.
    ///
    /// Sceglierne uno più fine costerebbe letture inutili; uno più grosso farebbe scalettare la
    /// waveform, perché lo stesso bin verrebbe disegnato su più colonne.
    public func level(framesPerPixel: Double) -> PeaksLevel {
        guard let finest = levels.first else {
            return PeaksLevel(binSize: 1, bins: [])
        }
        var chosen = finest
        for level in levels where Double(level.binSize) <= framesPerPixel {
            chosen = level
        }
        return chosen
    }
}
