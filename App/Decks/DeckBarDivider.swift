import AppKit
import SwiftUI

/// La maniglia fra il contenuto e la fascia dei deck.
///
/// Sostituisce il divisore di `VSplitView`, che è stato tolto: quello è un `NSSplitView`, e non
/// propagava ai suoi figli l'inset della toolbar della finestra — il titolo della scaletta
/// finiva scritto sopra la prima riga della lista. Con una `VStack` normale il contenuto sta al
/// suo posto, e l'altezza della fascia diventa un numero che decidiamo noi invece di una
/// divisione che il framework rifà a modo suo ogni volta che cambia la vista sopra.
struct DeckBarDivider: View {
    @Binding var height: Double

    @State private var dragAnchor: Double?
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.separator)
                .frame(height: 1)

            Capsule()
                .fill(isHovering ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 56, height: 4)
        }
        .frame(maxWidth: .infinity)
        // Dodici punti, non nove: è una maniglia che si cerca col mouse, e tre punti in più sono
        // la differenza fra prenderla al primo colpo e provarci due volte.
        .frame(height: 12)
        .background(Color(nsColor: .underPageBackgroundColor))
        .contentShape(Rectangle())
        .onHover { inside in
            isHovering = inside
            // Il cursore dice che si può trascinare, come su un divisore vero.
            if inside { NSCursor.resizeUpDown.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    let anchor = dragAnchor ?? height
                    if dragAnchor == nil { dragAnchor = anchor }
                    // Trascinando in su la fascia cresce: il bordo sale.
                    height = anchor - Double(value.translation.height)
                }
                .onEnded { _ in dragAnchor = nil }
        )
        .help("Trascina per cambiare l'altezza dei deck")
    }
}
