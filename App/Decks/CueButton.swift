import SwiftUI

/// Il tasto CUE.
///
/// A differenza degli altri controlli deve distinguere **pressione e rilascio**: in pausa sul cue
/// suona finché lo si tiene premuto e al rilascio torna indietro. `Button` reagisce al rilascio e
/// non basta, quindi la pressione la legge un `DragGesture(minimumDistance: 0)` — che scatta
/// subito al mouse down e finisce al mouse up anche se il puntatore è uscito dal tasto.
///
/// `isArmed` è la spia del CDJ: acceso vuol dire che la testina è sul cue, quindi il prossimo
/// colpo suona in anteprima invece di spostare il cue altrove.
struct CueButton: View {
    let isEnabled: Bool
    let isArmed: Bool
    let onPress: () -> Void
    let onRelease: () -> Void

    @State private var isPressed = false

    private static let cornerRadius: CGFloat = 5

    var body: some View {
        Text("CUE")
            .font(.caption.weight(.bold))
            .foregroundStyle(isPressed ? AnyShapeStyle(.black.opacity(0.85)) : AnyShapeStyle(.primary))
            .padding(.horizontal, 9)
            .frame(height: 20)
            .background(background, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(.separator)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        // `onChanged` arriva anche a ogni spostamento del puntatore: la
                        // pressione va eseguita una volta sola.
                        guard isEnabled, !isPressed else { return }
                        isPressed = true
                        onPress()
                    }
                    .onEnded { _ in
                        guard isPressed else { return }
                        isPressed = false
                        onRelease()
                    }
            )
            .help(helpText)
    }

    private var background: AnyShapeStyle {
        if isPressed {
            AnyShapeStyle(WaveformPalette.cue)
        } else if isArmed {
            AnyShapeStyle(WaveformPalette.cue.opacity(0.3))
        } else {
            AnyShapeStyle(Color(nsColor: .controlColor))
        }
    }

    private var helpText: String {
        guard isEnabled else { return "Nessun audio caricato" }
        return isArmed
            ? "Tieni premuto per ascoltare dal cue"
            : "Torna al cue, o lo sposta qui se il deck è in pausa"
    }
}
