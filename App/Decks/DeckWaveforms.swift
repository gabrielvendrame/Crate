import DJKit
import SwiftUI

/// La colonna centrale di un deck: overview, vista zoomata e riga degli hot cue.
///
/// **Vive in una vista sua, e non dentro `DeckStrip`, per una ragione di prestazioni.** SwiftUI
/// rivaluta il `body` di una vista quando cambia una qualsiasi delle proprietà osservabili che
/// quel `body` legge: tenendo waveform e fader di pitch nello stesso `body`, trascinare il fader
/// rifaceva anche il ramo delle waveform sessanta volte al secondo. E `WaveformZoomView` porta
/// dentro una **closure** (`livePosition`), che SwiftUI non sa confrontare: una vista che contiene
/// una closure risulta sempre «cambiata», quindi ogni giro finiva in `updateNSView` con i suoi
/// tocchi alla `MTKView`.
///
/// Isolata qui, la vista ha come unico dato un riferimento a `DeckState`: quando il `body` del
/// padre si rifà, questa risulta invariata e il suo sottoalbero viene saltato. Continua invece ad
/// aggiornarsi da sé quando cambia ciò che legge davvero — posizione, peaks, cue.
struct DeckWaveforms: View {
    @Environment(AppModel.self) private var model
    let deck: DeckState

    /// Posizione da cui è partito il trascinamento: senza ancora, ogni evento sommerebbe di nuovo
    /// l'intero spostamento e la waveform schizzerebbe via.
    @State private var scrubAnchor: Double?
    @State private var zoomAnchor: Double?

    var body: some View {
        VStack(spacing: 4) {
            WaveformOverviewView(
                peaks: deck.peaks,
                playheadSeconds: deck.playheadSeconds,
                durationSeconds: deck.durationSeconds,
                markers: deck.cueMarkers,
                onSeek: {
                    model.focus(deck.slot)
                    deck.seek(toSeconds: $0)
                }
            )
            .frame(height: 26)

            zoom

            HotCueRow(deck: deck)
        }
        .frame(maxWidth: .infinity)
    }

    private var zoom: some View {
        GeometryReader { geometry in
            ZStack {
                WaveformZoomView(
                    trackID: deck.track?.id,
                    peaks: deck.peaks,
                    playheadSeconds: deck.playheadSeconds,
                    visibleSeconds: deck.visibleSeconds,
                    markers: deck.cueMarkers,
                    isRunning: deck.isPlaying,
                    livePosition: deck.livePositionProvider
                )

                if deck.hasWaveform {
                    // La testina sta ferma al centro: è la waveform a scorrerle sotto.
                    Rectangle()
                        .fill(WaveformPalette.playhead)
                        .frame(width: 1.5)
                } else {
                    placeholder
                }
            }
            .contentShape(Rectangle())
            .gesture(scrubGesture(width: geometry.size.width))
            .simultaneousGesture(zoomGesture)
        }
        // Il minimo è quello che si vede quando la fascia dei deck viene schiacciata al suo
        // pavimento — succede con una scaletta vuota, dove `ContentUnavailableView` si prende
        // tutta l'altezza che può. Ottanta punti restano leggibili; a 64 la waveform era una
        // striscia.
        .frame(maxWidth: .infinity, minHeight: 80)
        .clipShape(RoundedRectangle(cornerRadius: 3))
    }

    @ViewBuilder
    private var placeholder: some View {
        VStack(spacing: 6) {
            if deck.isLoading {
                ProgressView().controlSize(.small)
                Text("Carico la waveform…")
            } else if let track = deck.track {
                Text(deck.loadError ?? "Waveform non disponibile.")
                if model.isAnalyzing(track) {
                    Text("Calcolo in corso…")
                } else {
                    Button("Calcola adesso") { model.reanalyze(track) }
                        .buttonStyle(.link)
                }
            } else {
                Text("Nessuna traccia caricata")
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
    }

    // MARK: - Gesti

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard width > 0, deck.durationSeconds > 0 else { return }
                model.focus(deck.slot)
                let anchor = scrubAnchor ?? deck.playheadSeconds
                if scrubAnchor == nil { scrubAnchor = anchor }
                let secondsPerPoint = deck.visibleSeconds / Double(width)
                deck.seek(toSeconds: anchor - Double(value.translation.width) * secondsPerPoint)
            }
            .onEnded { _ in scrubAnchor = nil }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let anchor = zoomAnchor ?? deck.visibleSeconds
                if zoomAnchor == nil { zoomAnchor = anchor }
                deck.visibleSeconds = min(64, max(1, anchor / value.magnification))
            }
            .onEnded { _ in zoomAnchor = nil }
    }
}
