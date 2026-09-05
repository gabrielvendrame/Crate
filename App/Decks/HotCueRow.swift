import AppKit
import DJKit
import SwiftUI

/// La riga degli otto hot cue di un deck.
///
/// Sta **sotto la waveform zoomata**, larga come lei: nella colonna di sinistra non ci starebbe
/// senza rubare larghezza alle waveform, che è la cosa che non si può togliere.
struct HotCueRow: View {
    let deck: DeckState

    @Environment(\.deckIsNarrow) private var isNarrow
    @State private var editingSlot: Int?
    @State private var hoveredSlot: Int?

    /// Affiancando i deck gli otto pad si prendono quasi tutta la riga e alla nota non resta
    /// niente: lì la nota va **sotto**, su una seconda riga, invece di essere schiacciata a due
    /// parole. È il compromesso previsto quando la disposizione a due colonne è stata chiesta.
    var body: some View {
        if isNarrow {
            VStack(alignment: .leading, spacing: 2) {
                pads
                HStack(spacing: 8) {
                    hoveredNote
                    Spacer(minLength: 0)
                    BeatJumpControl(deck: deck)
                    zoomLabel
                }
                // Diciotto e non dodici: la riga adesso porta anche i tasti di salto, che sono
                // alti quanto un tasto di nudge. Sono i sei punti in più nel minimo della fascia
                // affiancata.
                .frame(height: 18)
            }
        } else {
            pads
        }
    }

    private var pads: some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                ForEach(Array(CuePoint.hotcueSlotRange), id: \.self) { slot in
                    HotCuePad(
                        slot: slot,
                        cue: deck.hotCues[slot],
                        isEnabled: deck.track != nil,
                        onPress: { press(slot: slot) },
                        onEdit: { editingSlot = slot },
                        onDelete: { deck.deleteHotCue(slot: slot) },
                        onHover: { hovering in hover(slot: slot, isHovering: hovering) }
                    )
                    .popover(isPresented: editingBinding(for: slot), arrowEdge: .top) {
                        if let cue = deck.hotCues[slot] {
                            HotCueNoteEditor(cue: cue) { deck.update(cue: $0) }
                        }
                    }
                }
            }

            if !isNarrow {
                hoveredNote
                Spacer(minLength: 0)
                BeatJumpControl(deck: deck)
                zoomLabel
            }
        }
    }

    /// Il livello di zoom, che finiva nella colonna del pitch: là adesso c'è il fader.
    private var zoomLabel: some View {
        Text(String(format: "zoom %.0f s", deck.visibleSeconds))
            .font(.caption2)
            .foregroundStyle(.tertiary)
    }

    /// La nota del pad sotto il puntatore, accanto alla riga.
    ///
    /// Non è un popover né un tooltip di sistema: sta **sempre nello stesso posto**, appare senza
    /// ritardo e non copre la waveform. Il tooltip di macOS resta come ripiego per la nota lunga,
    /// che qui viene troncata.
    @ViewBuilder
    private var hoveredNote: some View {
        if let slot = hoveredSlot, let cue = deck.hotCues[slot] {
            HStack(spacing: 6) {
                Text(Timecode.precise(cue.positionSeconds))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(CuePalette.color(at: cue.colorIndex))

                if cue.label.isEmpty && cue.note.isEmpty {
                    Text("clic destro per annotare")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    if !cue.label.isEmpty {
                        Text(cue.label)
                            .font(.caption2.weight(.semibold))
                    }
                    if !cue.note.isEmpty {
                        Text(cue.note)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .lineLimit(2)
            .truncationMode(.tail)
        }
    }

    /// Passando da un pad all'altro i due eventi possono arrivare in qualsiasi ordine: senza il
    /// controllo sullo slot, l'uscita dal pad vecchio cancellerebbe l'entrata in quello nuovo.
    private func hover(slot: Int, isHovering: Bool) {
        if isHovering {
            hoveredSlot = slot
        } else if hoveredSlot == slot {
            hoveredSlot = nil
        }
    }

    /// Lo shift si legge dallo stato corrente dei modificatori: un `Button` di SwiftUI non
    /// riporta quali tasti erano premuti quando è stato cliccato.
    private func press(slot: Int) {
        if NSEvent.modifierFlags.contains(.shift) {
            deck.deleteHotCue(slot: slot)
        } else {
            deck.pressHotCue(slot: slot)
        }
    }

    private func editingBinding(for slot: Int) -> Binding<Bool> {
        Binding(
            get: { editingSlot == slot },
            set: { if !$0 { editingSlot = nil } }
        )
    }
}

/// Un pad: acceso col colore del suo slot quando c'è un hot cue, spento quando è libero.
private struct HotCuePad: View {
    let slot: Int
    let cue: CuePoint?
    let isEnabled: Bool
    let onPress: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onHover: (Bool) -> Void

    private static let cornerRadius: CGFloat = 4
    /// Sotto questa larghezza il numero dello slot non si legge più. È il pavimento su cui la riga
    /// smette di stringersi, e con due deck affiancati è la larghezza che si ottiene davvero.
    static let minimumPadWidth: CGFloat = 26

    var body: some View {
        Button(action: onPress) {
            VStack(spacing: 0) {
                Text("\(slot)")
                    .font(.caption2.weight(.bold))
                if let label = shortLabel {
                    Text(label)
                        .font(.system(size: 8))
                        .lineLimit(1)
                }
            }
            .foregroundStyle(cue == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.black.opacity(0.85)))
            // **Larghezza elastica, non fissa.** Con i pad a 46 punti la riga degli otto ne
            // pretende 396, e affiancando i deck la fascia diventava più larga della finestra:
            // il fader di pitch del deck B e metà mixer finivano fuori dallo schermo. Ora i pad
            // si stringono fino a `minimumPadWidth` e la riga sta dentro qualsiasi colonna.
            .frame(maxWidth: 46, minHeight: 22, maxHeight: 22)
            .frame(minWidth: Self.minimumPadWidth)
            .background(background, in: RoundedRectangle(cornerRadius: Self.cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Self.cornerRadius)
                    .strokeBorder(.separator)
            )
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { onHover($0 && cue != nil) }
        .help(helpText)
        .contextMenu {
            if cue != nil {
                Button("Modifica nome e nota…") { onEdit() }
                Divider()
                Button("Cancella hot cue", role: .destructive) { onDelete() }
            }
        }
    }

    /// Sul pad ci stanno pochi caratteri: il nome intero e la nota vivono nel tooltip e nel
    /// popover di modifica.
    private var shortLabel: String? {
        guard let label = cue?.label, !label.isEmpty else { return nil }
        return label
    }

    private var background: AnyShapeStyle {
        guard let cue else { return AnyShapeStyle(Color.black.opacity(0.25)) }
        return AnyShapeStyle(CuePalette.color(at: cue.colorIndex))
    }

    private var helpText: String {
        guard isEnabled else { return "Nessuna traccia caricata" }
        guard let cue else {
            return "Slot \(slot) libero — premi per memorizzare il punto in cui sei"
        }
        var lines = ["\(slot) · \(Timecode.precise(cue.positionSeconds))"]
        if !cue.label.isEmpty { lines.append(cue.label) }
        if !cue.note.isEmpty { lines.append(cue.note) }
        lines.append("⇧ + clic per cancellare")
        return lines.joined(separator: "\n")
    }
}

/// Nome breve e nota di un hot cue. Salva alla chiusura, così non serve confermare niente.
private struct HotCueNoteEditor: View {
    let cue: CuePoint
    let onSave: (CuePoint) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var label: String
    @State private var note: String

    init(cue: CuePoint, onSave: @escaping (CuePoint) -> Void) {
        self.cue = cue
        self.onSave = onSave
        _label = State(initialValue: cue.label)
        _note = State(initialValue: cue.note)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(CuePalette.color(at: cue.colorIndex))
                    .frame(width: 14, height: 14)
                Text("Hot cue \(cue.hotcueSlot ?? 0)")
                    .font(.callout.weight(.semibold))
                Text(Timecode.precise(cue.positionSeconds))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            TextField("Nome breve", text: $label)
                .textFieldStyle(.roundedBorder)
            TextField("Nota: cosa fare qui, con cosa lega", text: $note, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(3...6)

            HStack {
                Spacer()
                Button("Fatto") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
        .frame(width: 280)
        .onDisappear { save() }
    }

    private func save() {
        var updated = cue
        updated.label = label.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
        guard updated != cue else { return }
        onSave(updated)
    }
}
