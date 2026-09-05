import SwiftUI
import DJKit

/// La fascia dei deck, sempre visibile in fondo alla finestra.
///
/// I deck sono **impilati di default**, A sopra e B sotto: così ogni waveform occupa tutta la
/// larghezza disponibile e scorre in orizzontale, tempo da sinistra a destra. Affiancandoli ogni
/// waveform ne ha metà — è la disposizione alternativa chiesta da Gabriel, non un pari merito, e
/// il compromesso è scritto nei vincoli di `CLAUDE.md`.
///
/// In tutti e due i casi il mixer sta **fra** i due deck, come su un banco vero: sotto quando
/// sono impilati, in mezzo alle due colonne quando sono affiancati.
struct DeckBarView: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }

    var body: some View {
        Group {
            switch model.deckLayout {
            case .stacked:
                VStack(spacing: 1) {
                    DeckStrip(deck: model.deckA)
                    MixerStrip()
                    DeckStrip(deck: model.deckB)
                }
            case .sideBySide:
                VStack(spacing: 1) {
                    HStack(spacing: 1) {
                        DeckStrip(deck: model.deckA)
                        DeckStrip(deck: model.deckB)
                    }
                    MixerStrip()
                }
            }
        }
        .background(.quaternary)
    }
}

private struct DeckStrip: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    let deck: DeckState

    @State private var isDropTargeted = false
    @State private var isGridEditorPresented = false

    var body: some View {
        HStack(spacing: 12) {
            identity
            DeckWaveforms(deck: deck)
            pitch
        }
        // Affiancati, la colonna di sinistra si stringe: con la larghezza di prima resterebbe
        // meno di metà finestra alle waveform, che è la cosa che non si può comprimere.
        .environment(\.deckIsNarrow, model.deckLayout == .sideBySide)
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .leading) {
            // La barra dice a chi parlano i tasti 1–8.
            Rectangle()
                .fill(isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.clear))
                .frame(width: 3)
        }
        // Trascinare una traccia — dalla libreria o da una riga di scaletta — su un deck la
        // carica. Una riga di nota non porta nessuna traccia e viene rifiutata.
        .dropDestination(for: RowDrag.self) { drags, _ in
            guard let trackID = drags.compactMap(\.trackID).first else { return false }
            model.loadTrack(id: trackID, on: deck.slot)
            return true
        } isTargeted: { isDropTargeted = $0 }
        .overlay {
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.tint, lineWidth: 2)
                    .padding(2)
            }
        }
    }

    private var isFocused: Bool { model.focusedDeckSlot == deck.slot }

    @Environment(\.deckIsNarrow) private var isNarrow

    // MARK: - Colonna sinistra

    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("DECK \(deck.slot.rawValue)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(isFocused ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))

            Text(deck.track?.displayName ?? "Vuoto")
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .truncationMode(.middle)
                .foregroundStyle(deck.track == nil ? .tertiary : .primary)

            if let track = deck.track {
                DeckLabelPhoto(track: track)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text(Timecode.precise(deck.playheadSeconds))
                    .monospacedDigit()
                Text("/")
                    .foregroundStyle(.tertiary)
                Text(Timecode.short(deck.durationSeconds))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)

            transport

            if let error = deck.playbackError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
                    .help(error)
            }
        }
        .frame(width: isNarrow ? 118 : 150, alignment: .leading)
        .contentShape(Rectangle())
        // Un clic sulla colonna di sinistra sposta il fuoco: sui pulsanti il clic arriva a loro,
        // che il fuoco lo spostano comunque.
        .onTapGesture { model.focus(deck.slot) }
    }

    private var transport: some View {
        HStack(spacing: 6) {
            Button(
                deck.isPlaying ? "Pausa" : "Riproduci",
                systemImage: deck.isPlaying ? "pause.fill" : "play.fill"
            ) {
                deck.togglePlay()
                model.focus(deck.slot)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!deck.canPlay)
            .help(deck.canPlay ? "Riproduci o metti in pausa" : "Nessun audio caricato")

            CueButton(
                isEnabled: deck.canPlay,
                isArmed: deck.isAtCue && !deck.isPlaying,
                onPress: {
                    model.focus(deck.slot)
                    deck.pressCue()
                },
                onRelease: { deck.releaseCue() }
            )
        }
    }

    // MARK: - Colonna destra

    private var pitch: some View {
        @Bindable var deck = deck

        return VStack(spacing: 3) {
            Text("PITCH")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)

            PitchFader(percent: $deck.pitchPercent, range: DeckEngine.pitchRangePercent)
                .frame(maxHeight: .infinity)
                .help("Trascina per cambiare velocità · doppio clic per tornare a zero")

            Text(pitchLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(deck.pitchPercent == 0 ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))

            bpmButton

            HStack(spacing: 4) {
                NudgeButton(
                    direction: .backward,
                    isEnabled: deck.canPlay,
                    onTap: { nudge(forward: false) },
                    onBendStart: { bend(forward: false) },
                    onBendEnd: { deck.endBend() }
                )
                NudgeButton(
                    direction: .forward,
                    isEnabled: deck.canPlay,
                    onTap: { nudge(forward: true) },
                    onBendStart: { bend(forward: true) },
                    onBendEnd: { deck.endBend() }
                )
            }
        }
        .frame(width: 68)
    }

    private var pitchLabel: String {
        String(format: "%+.1f%%", deck.pitchPercent)
    }

    /// Il display del BPM è anche il modo di aprire l'editor della griglia: è il numero che si
    /// guarda quando si sospetta che la griglia non torni, quindi è lì che si va a cercare il
    /// posto per correggerla.
    private var bpmButton: some View {
        Button {
            model.focus(deck.slot)
            isGridEditorPresented = true
        } label: {
            Text(bpmLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(deck.hasBeatgrid ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(deck.track == nil)
        .help(deck.hasBeatgrid ? "BPM effettivo · clic per correggere la griglia" : "Nessuna griglia · clic per metterne una")
        .popover(isPresented: $isGridEditorPresented, arrowEdge: .leading) {
            BeatgridEditor(deck: deck)
        }
        // Il tasto `G` chiede l'editor del deck attivo: la richiesta arriva dal modello, e il
        // deck a cui è indirizzata se la consuma.
        .onChange(of: model.gridEditorRequest) { _, request in
            guard request == deck.slot else { return }
            model.gridEditorRequest = nil
            isGridEditorPresented = deck.track != nil
        }
    }

    /// **Il BPM effettivo, non quello della traccia**: con il fader a +4% è quello che si sente, ed
    /// è il numero da confrontare con l'altro deck. Il tempo scritto in tabella si legge
    /// nell'editor, che è dove serve.
    ///
    /// Senza analisi del tempo il BPM non c'è: meglio un trattino che un numero inventato.
    private var bpmLabel: String {
        guard let bpm = deck.effectiveBPM else { return "— BPM" }
        return String(format: "%.1f BPM", bpm)
    }

    private func nudge(forward: Bool) {
        model.focus(deck.slot)
        deck.nudge(forward: forward)
    }

    private func bend(forward: Bool) {
        model.focus(deck.slot)
        deck.startBend(forward: forward)
    }
}
