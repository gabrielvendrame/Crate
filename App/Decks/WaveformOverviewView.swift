import SwiftUI
import DJKit

/// La traccia intera in una striscia sola: serve a sapere dove si è dentro il pezzo e a saltare
/// altrove con un clic.
///
/// Disegnata con `Canvas`: sono poche centinaia di colonne, statiche finché non cambia la traccia.
/// La testina è un overlay separato proprio per questo — se stesse dentro il `Canvas`, muoverla
/// costringerebbe a ridisegnare tutte le colonne a ogni frame.
struct WaveformOverviewView: View {
    let peaks: Peaks?
    let playheadSeconds: Double
    let durationSeconds: Double
    /// Hot cue, memory cue e cue di lavoro.
    ///
    /// Qui i marker sono overlay SwiftUI, non disegno dentro uno shader come nella vista zoomata,
    /// e per un motivo preciso: **nell'overview non scorrono**. La loro x dipende solo da
    /// posizione e durata, quindi non c'è niente da tenere in sincrono con l'audio — e questo
    /// permette di scriverci sopra il numero dello slot, che uno shader non saprebbe disegnare.
    let markers: [CueMarker]
    let onSeek: (Double) -> Void

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                Canvas(rendersAsynchronously: true) { context, size in
                    draw(context: context, size: size, peaks: peaks)
                }

                if durationSeconds > 0 {
                    ForEach(markers) { marker in
                        markerView(marker, x: markerX(marker.seconds, width: geometry.size.width))
                    }
                }

                if durationSeconds > 0 {
                    Rectangle()
                        .fill(WaveformPalette.playhead)
                        .frame(width: 1.5)
                        .offset(x: playheadX(width: geometry.size.width))
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in seek(x: value.location.x, width: geometry.size.width) }
            )
        }
        .background(WaveformPalette.background)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    /// La bandierina in cima serve a trovare un cue su una striscia alta 26 punti: la sola linea
    /// verticale, in mezzo alla waveform, si perde.
    @ViewBuilder
    private func markerView(_ marker: CueMarker, x: CGFloat) -> some View {
        ZStack(alignment: .top) {
            Rectangle()
                .fill(marker.color)
                .frame(width: 1)

            if let badge = marker.badge {
                Text(badge)
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.black.opacity(0.85))
                    .frame(width: Self.markerWidth, height: 9)
                    .background(marker.color, in: RoundedRectangle(cornerRadius: 2))
            } else {
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 6))
                    .foregroundStyle(marker.color)
            }
        }
        .frame(width: Self.markerWidth)
        .offset(x: x)
    }

    private static let markerWidth: CGFloat = 10

    private func playheadX(width: CGFloat) -> CGFloat {
        guard durationSeconds > 0 else { return 0 }
        let fraction = min(1, max(0, playheadSeconds / durationSeconds))
        return CGFloat(fraction) * max(0, width - 1.5)
    }

    /// La x della bandierina, centrata sul punto e tenuta dentro i bordi: un cue a zero
    /// altrimenti finirebbe mezzo tagliato dall'angolo arrotondato.
    private func markerX(_ seconds: Double, width: CGFloat) -> CGFloat {
        guard durationSeconds > 0 else { return 0 }
        let fraction = min(1, max(0, seconds / durationSeconds))
        let centered = CGFloat(fraction) * max(0, width - 1) - Self.markerWidth / 2
        return min(max(0, centered), max(0, width - Self.markerWidth))
    }

    private func seek(x: CGFloat, width: CGFloat) {
        guard width > 0, durationSeconds > 0 else { return }
        let fraction = min(1, max(0, Double(x / width)))
        onSeek(fraction * durationSeconds)
    }

    private func draw(context: GraphicsContext, size: CGSize, peaks: Peaks?) {
        let centerY = size.height / 2
        context.stroke(
            Path { path in
                path.move(to: CGPoint(x: 0, y: centerY))
                path.addLine(to: CGPoint(x: size.width, y: centerY))
            },
            with: .color(WaveformPalette.centerLine),
            lineWidth: 1
        )

        guard let peaks, peaks.frameCount > 0, size.width >= 1, size.height >= 2 else { return }
        let columns = Int(size.width)
        guard columns > 0 else { return }

        let framesPerColumn = Double(peaks.frameCount) / Double(columns)
        let level = peaks.level(framesPerPixel: framesPerColumn)
        guard !level.bins.isEmpty else { return }

        let scale = size.height / 2 * WaveformPalette.amplitudeScale

        for column in 0..<columns {
            let firstBin = Int(Double(column) * framesPerColumn) / level.binSize
            guard firstBin < level.bins.count else { break }
            let lastBin = min(
                max(Int(Double(column + 1) * framesPerColumn) / level.binSize, firstBin + 1),
                level.bins.count
            )

            var minimum: Float = 0
            var maximum: Float = 0
            var low: Float = 0
            var mid: Float = 0
            var high: Float = 0
            for index in firstBin..<lastBin {
                let bin = level.bins[index]
                minimum = min(minimum, bin.minimum)
                maximum = max(maximum, bin.maximum)
                low = max(low, bin.low)
                mid = max(mid, bin.mid)
                high = max(high, bin.high)
            }

            let top = centerY - CGFloat(maximum) * scale
            let bottom = centerY - CGFloat(minimum) * scale
            let rect = CGRect(
                x: CGFloat(column),
                y: top,
                width: 1,
                height: max(1, bottom - top)
            )
            context.fill(
                Path(rect),
                with: .color(WaveformPalette.color(low: low, mid: mid, high: high))
            )
        }
    }
}
