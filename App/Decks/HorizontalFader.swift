import SwiftUI

/// Un fader orizzontale: crossfader e gain del mixer.
///
/// Scritto a mano e **non con `Slider`** per un motivo di prestazioni, non di estetica. Lo
/// `Slider` di macOS è un controllo AppKit: tenendolo premuto il run loop entra in modalità di
/// tracking, e in quella modalità il timer di disegno della waveform non scatta — la waveform si
/// inchiodava mentre si muoveva il crossfader. Un `DragGesture` di SwiftUI non apre nessun loop
/// di tracking, quindi tutto continua a muoversi.
///
/// Il display link della waveform ora è registrato in `.common` e regge comunque il tracking, ma
/// questi fader restano i suoi: il gesto è più diretto e il fader somiglia a quello di un mixer
/// invece che a un controllo di sistema.
struct HorizontalFader: View {
    @Binding var value: Double
    /// Valore a cui torna il doppio clic: 0,5 per il crossfader, 1 per un gain.
    let resetValue: Double

    private static let trackHeight: CGFloat = 4
    private static let knobWidth: CGFloat = 11
    private static let knobHeight: CGFloat = 16

    @State private var dragAnchor: Double?

    var body: some View {
        GeometryReader { geometry in
            let travel = max(0, geometry.size.width - Self.knobWidth)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.quaternary)
                    .frame(height: Self.trackHeight)
                    .frame(maxHeight: .infinity)

                RoundedRectangle(cornerRadius: 2.5)
                    .fill(Color(nsColor: .controlColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 2.5)
                            .strokeBorder(.separator)
                    )
                    .frame(width: Self.knobWidth, height: Self.knobHeight)
                    .offset(x: travel * clamped(value))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(drag(travel: travel))
            .onTapGesture(count: 2) { value = resetValue }
        }
        .frame(height: Self.knobHeight)
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { gesture in
                guard travel > 0 else { return }
                let anchor = dragAnchor ?? value
                if dragAnchor == nil { dragAnchor = anchor }
                value = clamped(anchor + Double(gesture.translation.width / travel))
            }
            .onEnded { _ in dragAnchor = nil }
    }

    private func clamped(_ raw: Double) -> Double {
        min(max(0, raw), 1)
    }
}
