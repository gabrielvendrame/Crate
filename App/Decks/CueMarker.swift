import DJKit
import SwiftUI

/// Un punto da segnare sulla waveform.
///
/// Mette nella stessa lista tre cose che si disegnano allo stesso modo ma vogliono dire cose
/// diverse: gli hot cue (colorati per slot, con il numero), i memory cue (i punti annotati senza
/// slot) e il cue di lavoro, quello che il tasto CUE sposta. Le viste ricevono questa lista e non
/// sanno niente di `CuePoint` né di `DeckEngine`.
struct CueMarker: Identifiable, Equatable {
    enum Kind: Equatable {
        case hotCue(slot: Int)
        case memoryCue
        /// Il cue del tasto CUE. Non sta nel database: vive in RAM e si sposta a ogni colpo.
        case workingCue
    }

    let id: String
    let seconds: Double
    let kind: Kind
    /// Indice di colore del cue point. Per gli hot cue viene dallo slot, ma sta nel database e
    /// potrà essere cambiato a mano.
    let colorIndex: Int

    init(id: String, seconds: Double, kind: Kind, colorIndex: Int = 0) {
        self.id = id
        self.seconds = seconds
        self.kind = kind
        self.colorIndex = colorIndex
    }

    init(cuePoint: CuePoint) {
        id = cuePoint.id
        seconds = cuePoint.positionSeconds
        kind = cuePoint.hotcueSlot.map { Kind.hotCue(slot: $0) } ?? .memoryCue
        colorIndex = cuePoint.colorIndex
    }

    /// Il marker del cue di lavoro, che è sempre uno solo.
    static func working(atSeconds seconds: Double) -> CueMarker {
        CueMarker(id: "working-cue", seconds: seconds, kind: .workingCue)
    }

    var rgb: SIMD3<Double> {
        switch kind {
        case .hotCue: CuePalette.rgb(at: colorIndex)
        case .memoryCue: CuePalette.memoryCueRGB
        case .workingCue: WaveformPalette.cueRGB
        }
    }

    var color: Color {
        Color(red: rgb.x, green: rgb.y, blue: rgb.z)
    }

    /// Il numero da scrivere sulla bandierina, se ne ha una.
    var badge: String? {
        switch kind {
        case .hotCue(let slot): "\(slot)"
        case .memoryCue, .workingCue: nil
        }
    }
}
