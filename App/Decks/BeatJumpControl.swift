import DJKit
import SwiftUI

/// I due tasti di salto e la taglia scelta, per un deck: `◀ 16 ▶`.
///
/// Sta nella riga degli hot cue, a destra, e non nella colonna del pitch: quella colonna è larga
/// 90 punti e ci stanno già fader, percentuale, i due `−`/`+`, il BPM e i due tasti di nudge. Qui
/// invece lo spazio a destra dopo «zoom 8 s» c'era, ed è **accanto ai pad**, che è il posto giusto
/// per un comando che sposta la testina di una quantità decisa in anticipo.
///
/// Il numero in mezzo è il menu della taglia: non serve un terzo comando per cambiarla, e messo
/// così si legge sempre di quanto si sta per saltare.
struct BeatJumpControl: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    let deck: DeckState

    private static let cornerRadius: CGFloat = 4
    private static let height: CGFloat = 18

    var body: some View {
        HStack(spacing: 2) {
            jumpButton(forward: false)
            sizeMenu
            jumpButton(forward: true)
        }
        .opacity(deck.canBeatJump ? 1 : 0.4)
    }

    private func jumpButton(forward: Bool) -> some View {
        Button {
            model.focus(deck.slot)
            deck.jump(forward: forward)
        } label: {
            Image(systemName: forward ? "forward.end.fill" : "backward.end.fill")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 22, height: Self.height)
                .background(
                    Color(nsColor: .controlColor),
                    in: RoundedRectangle(cornerRadius: Self.cornerRadius)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(.separator)
                )
                .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
        }
        .buttonStyle(.plain)
        .disabled(!deck.canBeatJump)
        // Tenuto premuto continua a saltare: è il modo di attraversare un brano lungo senza
        // trascinare la waveform e senza perdere la battuta.
        .buttonRepeatBehavior(.enabled)
        // Senza, l'accessibilità legge il nome del simbolo — «Go To Start», «Go To End» — che qui
        // vuol dire l'esatto contrario: non si va all'inizio della traccia, si salta di poche
        // battute. Visto nell'albero AX provando l'app.
        .accessibilityLabel(forward ? "Salta avanti" : "Salta indietro")
        .help(helpText(forward: forward))
    }

    private var sizeMenu: some View {
        Menu {
            ForEach(BeatJumpSize.allCases, id: \.self) { size in
                Button {
                    model.focus(deck.slot)
                    deck.beatJumpSize = size
                } label: {
                    // Le misure accanto alle battute perché è in misure che si pensa una frase:
                    // 16 battute sono quattro misure, ed è la stessa cosa detta due volte apposta.
                    Text("\(size.label) battute · \(size.bars) misure")
                }
            }
        } label: {
            Text(deck.beatJumpSize.label)
                .font(.caption2.monospacedDigit().weight(.semibold))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 26, height: Self.height)
        .background(
            Color(nsColor: .controlColor),
            in: RoundedRectangle(cornerRadius: Self.cornerRadius)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Self.cornerRadius).strokeBorder(.separator)
        )
        .disabled(!deck.canBeatJump)
        .accessibilityLabel("Taglia del salto")
        .help("Di quante battute saltano i due tasti")
    }

    private func helpText(forward: Bool) -> String {
        guard deck.canBeatJump else {
            return "Nessuna griglia: senza BPM non si sa quanto dura una battuta"
        }
        let size = deck.beatJumpSize
        let direction = forward ? "Avanti" : "Indietro"
        let key = forward ? "." : ","
        return "\(direction) di \(size.label) battute (\(size.bars) misure) · tasto \(key)"
    }
}
