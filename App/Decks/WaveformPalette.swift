import SwiftUI

/// I colori con cui si dipinge la waveform, uno per banda di frequenza.
///
/// Blu i bassi, verde i medi, arancio gli alti: è la convenzione di rekordbox, e serve a
/// riconoscere a colpo d'occhio dove entra la cassa e dove resta solo un cappello.
///
/// **Le stesse terne stanno anche in `Waveform.metal`**, perché il fragment shader mescola i
/// colori per conto suo: se si cambiano qui vanno cambiate anche lì.
enum WaveformPalette {
    static let low = SIMD3<Double>(0.16, 0.47, 0.98)
    static let mid = SIMD3<Double>(0.22, 0.80, 0.42)
    static let high = SIMD3<Double>(0.98, 0.65, 0.16)

    /// Guadagni di presentazione applicati alle tre bande prima di mescolarle.
    ///
    /// Non sono una correzione dei dati, che restano l'RMS vero: servono a compensare la
    /// pendenza naturale dello spettro musicale. Misurato su un brano reale, l'RMS medio nei
    /// passaggi forti è **low 0,278 · mid 0,100 · high 0,011**: senza compenso ogni waveform
    /// risulterebbe blu dall'inizio alla fine e il colore non direbbe più niente. Con questi
    /// guadagni un passaggio pieno tende al verde-azzurro, un drop di cassa vira al blu, e un
    /// passaggio di soli cappelli all'arancio.
    static let bandGain = SIMD3<Double>(1, 3, 12)

    /// Quanto della metà altezza usa una waveform a fondo scala. Il margine serve perché una
    /// traccia masterizzata forte supera l'unità dopo la decodifica — misurato 1,04 — e senza
    /// margine toccherebbe i bordi restando tagliata.
    static let amplitudeScale = 0.95

    /// Sfondo dei riquadri di waveform e linea dello zero.
    static let background = Color(red: 0.07, green: 0.07, blue: 0.09)
    static let centerLine = Color.white.opacity(0.12)
    static let playhead = Color(red: 1.0, green: 0.25, blue: 0.25)

    /// Marker del cue di lavoro. Bianco appena azzurrato di proposito: le tre bande occupano
    /// blu, verde e arancio e la testina è rossa, quindi è l'unica tinta che non si confonde con
    /// niente. Gli hot cue hanno un colore per slot (`CuePalette`) e restano distinguibili.
    /// **La stessa terna sta in `Waveform.metal` come `kWorkingCueColor`.**
    static let cueRGB = SIMD3<Double>(0.92, 0.96, 1.0)
    static let cue = Color(red: cueRGB.x, green: cueRGB.y, blue: cueRGB.z)

    /// Mescola le tre tinte in proporzione ai livelli di banda.
    ///
    /// Dopo la miscela la luminosità viene riportata al massimo: l'altezza della colonna dice già
    /// quanto è forte il segnale, il colore deve dire *solo* com'è distribuito nello spettro. Se
    /// non si normalizzasse, i passaggi piano risulterebbero grigi e illeggibili.
    static func color(low lowLevel: Float, mid midLevel: Float, high highLevel: Float) -> Color {
        let weighted = SIMD3<Double>(Double(lowLevel), Double(midLevel), Double(highLevel))
            * bandGain
        let total = weighted.x + weighted.y + weighted.z
        guard total > 1e-6 else { return Color(white: 0.35) }

        var mixed =
            low * (weighted.x / total)
            + mid * (weighted.y / total)
            + high * (weighted.z / total)

        let peak = max(mixed.x, max(mixed.y, mixed.z))
        if peak > 1e-6 { mixed *= 0.98 / peak }

        return Color(red: mixed.x, green: mixed.y, blue: mixed.z)
    }
}
