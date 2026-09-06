import SwiftUI

/// Un tasto di nudge: **un colpetto sposta, tenuto premuto spinge**.
///
/// Sono due gesti diversi perché servono a due cose diverse. Il colpetto sposta la testina di un
/// passo esatto, ed è quello che serve quando si guarda la waveform e si vede di quanto si è
/// fuori. Tenerlo premuto accelera finché lo si tiene, come il dito sul bordo del piatto: sposta
/// la fase senza lo schiocco che dà il salto, ed è quello che serve a orecchio, mentre le due
/// tracce suonano.
///
/// **La spinta parte all'istante**, e i due gesti non si contendono più il tasto: prima si
/// aspettava un quarto di secondo per capire quale dei due fosse, e quel ritardo si sentiva —
/// segnalato da Gabriel il 2026-09-06. Adesso preme e accelera; il colpetto è il **minimo
/// garantito** che `DeckState.endBend(forward:heldFor:)` completa al rilascio se la spinta è
/// durata troppo poco per spostare altrettanto.
struct NudgeButton: View {
    enum Direction {
        case backward
        case forward

        var symbol: String {
            switch self {
            case .backward: "chevron.left"
            case .forward: "chevron.right"
            }
        }
    }

    let direction: Direction
    let isEnabled: Bool
    let onBendStart: () -> Void
    /// Riceve quanto è durata la pressione: serve a sapere quanto la spinta ha già spostato.
    let onBendEnd: (Double) -> Void

    private static let cornerRadius: CGFloat = 4

    @State private var pressedAt: Date?
    @State private var isBending = false

    var body: some View {
        Image(systemName: direction.symbol)
            .font(.caption2.weight(.bold))
            .frame(width: 26, height: 18)
            .background(
                isBending ? AnyShapeStyle(.tint) : AnyShapeStyle(Color(nsColor: .controlColor)),
                in: RoundedRectangle(cornerRadius: Self.cornerRadius)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(.separator)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Self.cornerRadius))
            .gesture(gesture)
            .help(isEnabled ? "Preme e spinge subito · un tocco vale un colpetto di 10 ms" : "Nessun audio caricato")
    }

    private var gesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { _ in
                guard isEnabled, !isBending else { return }
                pressedAt = Date()
                isBending = true
                onBendStart()
            }
            .onEnded { _ in
                guard isBending else { return }
                isBending = false
                onBendEnd(Date().timeIntervalSince(pressedAt ?? Date()))
                pressedAt = nil
            }
    }
}
