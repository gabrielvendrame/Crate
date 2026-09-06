import SwiftUI

/// I colori dei cue: uno per slot di hot cue, più la tinta dei memory cue.
///
/// Otto tinte distribuite sulla ruota dei colori, **saltando il rosso puro**: quello è della
/// testina, e un marker rosso sulla waveform sarebbe indistinguibile da lei. Fuori sono anche il
/// bianco del cue di lavoro (`WaveformPalette.cueRGB`) e i tre colori delle bande di frequenza.
///
/// I valori stanno come terne perché servono in due forme: `Color` per SwiftUI e tre `float` per
/// il fragment shader, che non può leggere le costanti Swift. **Le stesse terne sono ricopiate in
/// `Waveform.metal`** come `kCueColors`: se si cambiano qui vanno cambiate anche lì.
enum CuePalette {
    static let rgb: [SIMD3<Double>] = [
        SIMD3(0.10, 0.78, 0.85),  // 1 · ciano
        SIMD3(0.25, 0.48, 0.98),  // 2 · blu
        SIMD3(0.55, 0.35, 0.95),  // 3 · viola
        SIMD3(0.92, 0.30, 0.80),  // 4 · magenta
        SIMD3(0.98, 0.40, 0.25),  // 5 · arancio rosso
        SIMD3(0.98, 0.62, 0.15),  // 6 · arancio
        SIMD3(0.95, 0.85, 0.20),  // 7 · giallo
        SIMD3(0.35, 0.82, 0.30),  // 8 · verde
    ]

    /// Come si chiamano, per il menu che sceglie il colore di un tag: in un menu di macOS un
    /// pallino colorato da solo non si distingue bene, e «viola» sì.
    static let names = [
        "Ciano", "Blu", "Viola", "Magenta", "Arancio rosso", "Arancio", "Giallo", "Verde",
    ]

    static func name(at index: Int) -> String {
        guard !names.isEmpty else { return "Colore" }
        let wrapped = ((index % names.count) + names.count) % names.count
        return names[wrapped]
    }

    /// I memory cue non hanno uno slot, quindi non hanno un colore proprio: grigio chiaro, più
    /// spento del bianco del cue di lavoro ma abbastanza acceso da vedersi sulla waveform.
    static let memoryCueRGB = SIMD3<Double>(0.75, 0.78, 0.85)

    /// La terna di un indice qualsiasi, ciclando: un `colorIndex` fuori scala arriva dal
    /// database e non deve far cadere niente.
    static func rgb(at index: Int) -> SIMD3<Double> {
        guard !rgb.isEmpty else { return SIMD3(0.5, 0.5, 0.5) }
        let wrapped = ((index % rgb.count) + rgb.count) % rgb.count
        return rgb[wrapped]
    }

    static func color(at index: Int) -> Color {
        let value = rgb(at: index)
        return Color(red: value.x, green: value.y, blue: value.z)
    }

    /// Colore predefinito di uno slot da 1 a 8.
    static func color(forSlot slot: Int) -> Color {
        color(at: slot - 1)
    }
}
