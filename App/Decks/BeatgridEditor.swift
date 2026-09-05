import DJKit
import SwiftUI

/// Il pannello per correggere a mano BPM e griglia, che si apre dal display del BPM del deck.
///
/// **Sta in un popover e non nella fascia del deck** per una ragione di spazio: la fascia deve
/// restare bassa perché sopra ci sono libreria e scaletta, e questi controlli servono una volta
/// per traccia — quando l'analisi ha sbagliato — non mentre si suona. Il display del BPM è già
/// lì, ed è la cosa che si guarda quando si sospetta che la griglia non torni.
struct BeatgridEditor: View {
    @Environment(AppModel.self) private var model
    let deck: DeckState

    /// Testo del campo BPM, tenuto separato dal valore: mentre si scrive "1", "12", "128" il
    /// numero passa da stati che non vanno scritti in tabella.
    @State private var bpmText = ""
    /// Istanti dei colpi di tap-tempo, dal più vecchio al più recente.
    @State private var taps: [Date] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            tempo
            Divider()
            downbeat
            Divider()
            footer
        }
        .padding(14)
        .frame(width: 292)
        .task(id: deck.track?.id) { loadFields() }
    }

    // MARK: - Intestazione

    private var header: some View {
        HStack {
            Text("Griglia · Deck \(deck.slot.rawValue)")
                .font(.callout.weight(.semibold))
            Spacer()
            if let grid = deck.beatgrid {
                Text(String(format: "%.2f BPM", grid.bpm))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else {
                Text("nessuna")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Tempo

    private var tempo: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("BPM")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)

                TextField("—", text: $bpmText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 78)
                    .monospacedDigit()
                    .onSubmit { commitBPM() }

                // ×2 e ÷2 raddrizzano l'errore di ottava, che è quello che il rilevamento
                // automatico sbaglia più spesso: 174 letto 87, o viceversa.
                Button("÷2") { deck.scaleBPM(by: 0.5); loadFields() }
                    .disabled(!deck.hasBeatgrid)
                    .help("Dimezza il tempo: usalo quando la griglia batte il doppio del pezzo")
                Button("×2") { deck.scaleBPM(by: 2); loadFields() }
                    .disabled(!deck.hasBeatgrid)
                    .help("Raddoppia il tempo")
            }

            HStack(spacing: 8) {
                Text("TAP")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)

                Button(action: tap) {
                    Text(tapLabel)
                        .frame(maxWidth: .infinity)
                }
                .help("Batti a tempo con il pezzo: dal quarto colpo il BPM si aggiorna a ogni battuta")

                Button("Azzera") { taps = [] }
                    .disabled(taps.isEmpty)
            }
        }
    }

    private var tapLabel: String {
        switch taps.count {
        case 0: "Batti a tempo"
        case 1..<Self.minimumTaps: "Ancora \(Self.minimumTaps - taps.count)…"
        default: String(format: "%.2f BPM", tappedBPM ?? 0)
        }
    }

    // MARK: - Downbeat

    private var downbeat: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("PRIMO 1")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 62, alignment: .leading)

                Button("Qui") { deck.alignDownbeatToPlayhead() }
                    .disabled(!deck.hasBeatgrid)
                    .help("Porta l'uno della misura sulla testina")

                Button {
                    deck.shiftGrid(bySeconds: -nudgeStep)
                } label: {
                    Image(systemName: "arrow.left")
                }
                .disabled(!deck.hasBeatgrid)

                Button {
                    deck.shiftGrid(bySeconds: nudgeStep)
                } label: {
                    Image(systemName: "arrow.right")
                }
                .disabled(!deck.hasBeatgrid)

                if let grid = deck.beatgrid {
                    Text(String(format: "%.3f s", grid.offsetSeconds))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            Text("Le frecce spostano di un millesimo, con ⇧ di un centesimo. Sulla waveform, ⌥ e trascina.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Con ⇧ il passo si fa dieci volte più grosso: è la scorciatoia che sui campi numerici di
    /// macOS ci si aspetta comunque.
    private var nudgeStep: Double {
        NSEvent.modifierFlags.contains(.shift)
            ? DeckState.gridCoarseNudgeSeconds
            : DeckState.gridNudgeSeconds
    }

    // MARK: - Piede

    private var footer: some View {
        HStack {
            if let track = deck.track {
                Button("Rileva di nuovo") { model.reanalyze(track) }
                    .disabled(model.isAnalyzing(track) || track.audioFilename == nil)
            }
            Spacer()
            Button("Togli la griglia", role: .destructive) {
                deck.setBeatgrid(nil)
                loadFields()
            }
            .disabled(!deck.hasBeatgrid)
        }
    }

    // MARK: - Tap tempo

    /// Sotto i quattro colpi un tap-tempo dice più del rumore della mano che del tempo del pezzo.
    private static let minimumTaps = 4
    /// Oltre due secondi fra un colpo e l'altro non si sta più battendo la stessa cosa: la serie
    /// riparte, invece di mediare due tentativi diversi.
    private static let tapTimeout = 2.0
    /// Quanti colpi si tengono: gli ultimi otto sono una decina di secondi di media, abbastanza
    /// per stabilizzarsi senza trascinarsi dietro l'inizio incerto.
    private static let tapWindow = 8

    private func tap() {
        let now = Date()
        if let last = taps.last, now.timeIntervalSince(last) > Self.tapTimeout {
            taps = []
        }
        taps.append(now)
        if taps.count > Self.tapWindow { taps.removeFirst(taps.count - Self.tapWindow) }

        if let bpm = tappedBPM {
            deck.setBPM(bpm)
            loadFields()
        }
    }

    /// Media degli intervalli fra i colpi tenuti, cioè la distanza fra il primo e l'ultimo divisa
    /// per quanti intervalli ci sono in mezzo: i singoli colpi storti si compensano da soli.
    private var tappedBPM: Double? {
        guard taps.count >= Self.minimumTaps, let first = taps.first, let last = taps.last
        else { return nil }
        let elapsed = last.timeIntervalSince(first)
        guard elapsed > 0 else { return nil }
        return 60 * Double(taps.count - 1) / elapsed
    }

    // MARK: - Campo BPM

    private func loadFields() {
        bpmText = deck.beatgrid.map { String(format: "%.2f", $0.bpm) } ?? ""
    }

    private func commitBPM() {
        // La virgola decimale è quella che si scrive davvero su una tastiera italiana.
        let normalized = bpmText.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else {
            loadFields()
            return
        }
        deck.setBPM(value)
        loadFields()
    }
}
