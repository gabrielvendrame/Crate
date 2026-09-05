import SwiftUI

/// Il fader di pitch, verticale, con lo **zero al centro e il più in basso**.
///
/// L'orientamento non è un'opzione: su un SL-1200 come su un CDJ, spingere il fader **verso il
/// basso accelera**. Invertirlo qui vorrebbe dire allenare il gesto sbagliato, e l'app esiste
/// perché ciò che si impara davanti allo schermo valga poi davanti al piatto.
///
/// Costruito a mano invece che con `Slider` per tre motivi: `Slider` è orizzontale e ruotarlo
/// porta dietro guai di layout, serve il **fermo allo zero** (che è quello che permette di
/// tornare a velocità nominale senza guardare), e servono le tacche a ±4 e ±8.
struct PitchFader: View {
    @Binding var percent: Double
    let range: Double

    /// Entro questo scostamento il fader si aggancia allo zero. Un decimo di percento è sotto la
    /// soglia di ciò che si sente, ed è ciò che rende lo zero ritrovabile a occhi chiusi.
    private static let detent = 0.12
    private static let knobHeight: CGFloat = 12
    private static let trackWidth: CGFloat = 3

    @State private var dragAnchor: Double?

    var body: some View {
        GeometryReader { geometry in
            let travel = max(0, geometry.size.height - Self.knobHeight)

            ZStack(alignment: .top) {
                ticks(height: geometry.size.height)

                Capsule()
                    .fill(.quaternary)
                    .frame(width: Self.trackWidth)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                knob
                    .offset(y: offset(travel: travel))
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .gesture(drag(travel: travel))
            // Doppio clic per tornare a velocità nominale, come rimettere a zero il fader.
            .onTapGesture(count: 2) { percent = 0 }
        }
        .frame(width: 34)
    }

    private var knob: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(nsColor: .controlColor))
            .overlay(
                RoundedRectangle(cornerRadius: 3)
                    .strokeBorder(.separator)
            )
            .overlay(
                Rectangle()
                    .fill(.secondary)
                    .frame(height: 1)
            )
            .frame(width: 28, height: Self.knobHeight)
    }

    /// Tacche a zero e a metà corsa per lato. Quella dello zero è più larga: è l'unica che serve
    /// trovare senza contare.
    private func ticks(height: CGFloat) -> some View {
        let travel = max(1, height - Self.knobHeight)
        return ForEach([-range, -range / 2, 0, range / 2, range], id: \.self) { value in
            let fraction = (value + range) / (2 * range)
            Rectangle()
                .fill(value == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(.quaternary))
                .frame(width: value == 0 ? 16 : 9, height: 1)
                .offset(y: Self.knobHeight / 2 + travel * fraction)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func offset(travel: CGFloat) -> CGFloat {
        let clamped = min(max(-range, percent), range)
        let fraction = (clamped + range) / (2 * range)
        return travel * fraction
    }

    private func drag(travel: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard travel > 0 else { return }
                let anchor = dragAnchor ?? percent
                if dragAnchor == nil { dragAnchor = anchor }
                // Verso il basso accelera: il segno della traslazione è già quello giusto.
                let delta = Double(value.translation.height / travel) * 2 * range
                percent = snapped(anchor + delta)
            }
            .onEnded { _ in dragAnchor = nil }
    }

    private func snapped(_ value: Double) -> Double {
        let clamped = min(max(-range, value), range)
        return abs(clamped) < Self.detent ? 0 : clamped
    }
}
