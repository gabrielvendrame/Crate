import Foundation

/// Di quante battute si sposta la testina con un colpo di salto.
///
/// **Battute, cioè quarti, non misure**: sono i valori del *beat jump* dei CDJ, dove 16 significa
/// quattro misure. Le quattro taglie coprono i due usi diversi che se ne fanno — 8 e 16 per
/// spostarsi dentro una frase, 32 e 64 per saltare al pezzo successivo del brano — e sotto le 8
/// battute non serve niente: lì si scorre la waveform.
public enum BeatJumpSize: Int, CaseIterable, Codable, Sendable {
    case eight = 8
    case sixteen = 16
    case thirtyTwo = 32
    case sixtyFour = 64

    public var beats: Int { rawValue }

    /// Quante misure da quattro quarti sono: 8 battute sono 2 misure, 64 sono 16.
    public var bars: Int { rawValue / Beatgrid.beatsPerBar }

    /// Come si scrive sul comando. Il numero nudo, come sui CDJ: chi lo usa conta in battute.
    public var label: String { "\(rawValue)" }
}
