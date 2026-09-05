import DJKit
import SwiftUI

/// L'editor di una scaletta: brani e note nella stessa lista, riordinabili insieme.
///
/// Le note sono righe come le altre e non un campo attaccato a un brano: se ne possono mettere
/// più d'una fra due pezzi, o una in testa, e si trascinano insieme a loro. È il modo in cui si
/// annota un set — «qui entra la cassa mentre l'altro esce», «questa attacca sul break» — e
/// quelle frasi appartengono al *passaggio*, non alla traccia.
struct PlaylistDetailView: View {
    @Environment(AppModel.self) private var model
    let playlistID: String

    @State private var entries: [PlaylistEntry] = []
    @State private var selection: Set<String> = []
    @State private var isRenaming = false
    @State private var draftName = ""

    private var playlist: Playlist? {
        model.playlistList.first { $0.id == playlistID }
    }

    var body: some View {
        content
            .navigationTitle(playlist?.name ?? "Scaletta")
            .toolbar { toolbarContent }
            .task(id: playlistID) { await observeEntries() }
            .onChange(of: playlistID) { selection = [] }
            .alert("Rinomina scaletta", isPresented: $isRenaming) {
                TextField("Nome", text: $draftName)
                Button("Rinomina") { commitRename() }
                Button("Annulla", role: .cancel) {}
            }
    }

    @ViewBuilder
    private var content: some View {
        if entries.isEmpty {
            ContentUnavailableView {
                Label("Scaletta vuota", systemImage: "list.bullet.rectangle")
            } description: {
                Text("Trascina qui i brani dalla libreria, o aggiungi una nota per cominciare.")
            } actions: {
                Button("Aggiungi nota") { model.addNote(to: playlistID) }
            }
            .dropDestination(for: RowDrag.self) { drags, _ in
                let ids = known(drags.compactMap(\.trackID))
                guard !ids.isEmpty else { return false }
                model.appendTracks(ids, to: playlistID)
                return true
            }
        } else {
            list
        }
    }

    private var list: some View {
        listBody
            // Il riassunto sta qui e non in `navigationSubtitle`: con la toolbar unificata il
            // titolo su due righe si sovrapponeva alla prima riga della lista.
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                    Divider()
                }
                .background(.bar)
            }
    }

    private var listBody: some View {
        List(selection: $selection) {
            ForEach(entries) { entry in
                row(for: entry)
                    .listRowInsets(EdgeInsets(top: 2, leading: 8, bottom: 2, trailing: 8))
                    .contextMenu { rowMenu(for: entry) }
            }
            // **Il riordino è `onMove`**, cioè il trascinamento nativo della lista: si prende una
            // riga da qualsiasi punto e la si porta dove serve.
            //
            // Ha un prezzo, ed è una scelta: `onMove` si prende il trascinamento delle righe,
            // quindi una riga di scaletta **non** si può trascinare su un deck — sarebbe lo stesso
            // gesto. Per quello ci sono i tastini A/B sulla riga, che sono anche più rapidi.
            // Provato il contrario (righe `draggable` e riordino fatto a mano nel drop) e il
            // riordino non funzionava più: fra i due, quello che serve tutti i giorni è il
            // riordino.
            .onMove { source, destination in move(from: source, to: destination) }
            // Il drop esterno sta sul `ForEach` perché è l'unico che riceve **l'indice di
            // inserimento**, e convive con `onMove`. Attenzione all'ordine degli argomenti della
            // closure: `(elementi, indice)`.
            // Il drop esterno sta sul `ForEach` perché è l'unico che riceve **l'indice di
            // inserimento**, e convive con `onMove`: verificato pilotando l'app, si riordina e
            // si inserisce dalla libreria senza che uno dei due rubi l'altro. Attenzione
            // all'ordine degli argomenti della closure: `(elementi, indice)`.
            .dropDestination(for: RowDrag.self) { drags, index in
                let ids = known(drags.compactMap(\.trackID))
                guard !ids.isEmpty else { return }
                model.insertTracks(ids, into: playlistID, at: index)
            }
        }
        .listStyle(.inset)
        .alternatingRowBackgrounds()
        .onDeleteCommand { deleteSelection() }
    }

    @ViewBuilder
    private func row(for entry: PlaylistEntry) -> some View {
        switch entry.item.kind {
        case .track:
            PlaylistTrackRow(
                entry: entry,
                number: trackNumbers[entry.id],
                deckBadge: deckBadge(for: entry),
                onLoad: { slot in load(entry, on: slot) }
            )
        case .note:
            PlaylistNoteRow(item: entry.item) { model.save(item: $0) }
                .id(entry.item.id)
        }
    }

    @ViewBuilder
    private func rowMenu(for entry: PlaylistEntry) -> some View {
        if entry.track != nil {
            Button("Carica sul deck A") { load(entry, on: .a) }
            Button("Carica sul deck B") { load(entry, on: .b) }
            Divider()
        }
        Button("Sposta su") { nudgeRow(entry, by: -1) }
            .disabled(index(of: entry) == 0)
        Button("Sposta giù") { nudgeRow(entry, by: 1) }
            .disabled(index(of: entry) >= entries.count - 1)
        Divider()
        Button("Aggiungi nota qui sotto") {
            model.addNote(to: playlistID, at: index(of: entry) + 1)
        }
        Divider()
        Button("Elimina dalla scaletta", role: .destructive) {
            model.deleteItems(ids: [entry.id], in: playlistID)
            selection.remove(entry.id)
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem {
            Button("Aggiungi nota", systemImage: "text.badge.plus") {
                model.addNote(to: playlistID, at: insertionIndexForSelection)
            }
            .help("Aggiungi una nota di passaggio, dopo la riga selezionata")
        }
        ToolbarItem {
            Button("Rinomina", systemImage: "pencil") {
                draftName = playlist?.name ?? ""
                isRenaming = true
            }
        }
    }

    // MARK: - Dati

    /// Osservazione continua invece di una lettura sola: la scaletta cambia anche da fuori — un
    /// brano eliminato dalla libreria lascia il suo segnaposto — e la lista deve accorgersene.
    private func observeEntries() async {
        guard let database = model.database, let playlists = model.playlists else { return }
        do {
            let observation = playlists.observeEntries(playlistID: playlistID)
            for try await value in observation.values(in: database.reader) {
                entries = value
            }
        } catch {
            model.transientError = "Non riesco a leggere la scaletta: \(error.localizedDescription)"
        }
    }

    private var summary: String {
        let tracks = entries.filter { $0.item.kind == .track }
        let seconds = tracks.reduce(0.0) { $0 + ($1.track?.durationSeconds ?? 0) }
        let notes = entries.count - tracks.count
        var parts = ["\(tracks.count) brani"]
        if notes > 0 { parts.append("\(notes) note") }
        if seconds > 0 { parts.append(Timecode.short(seconds)) }
        return parts.joined(separator: " · ")
    }

    /// Numerazione progressiva dei soli brani: le note non contano, altrimenti la scaletta non
    /// direbbe più «il quinto pezzo».
    private var trackNumbers: [String: Int] {
        var numbers: [String: Int] = [:]
        var next = 1
        for entry in entries where entry.item.kind == .track {
            numbers[entry.id] = next
            next += 1
        }
        return numbers
    }

    private func deckBadge(for entry: PlaylistEntry) -> String? {
        guard let trackID = entry.track?.id else { return nil }
        if model.deckA.track?.id == trackID { return "A" }
        if model.deckB.track?.id == trackID { return "B" }
        return nil
    }

    // MARK: - Azioni

    private func index(of entry: PlaylistEntry) -> Int {
        entries.firstIndex { $0.id == entry.id } ?? entries.count
    }

    private var insertionIndexForSelection: Int? {
        guard selection.count == 1, let id = selection.first,
              let index = entries.firstIndex(where: { $0.id == id })
        else { return nil }
        return index + 1
    }

    /// Ignora gli identificativi che non corrispondono a niente in libreria: un trascinamento
    /// arrivato da fuori non deve diventare una riga fantasma.
    private func known(_ ids: [String]) -> [String] {
        ids.filter { id in model.trackList.contains { $0.id == id } }
    }

    private func move(from source: IndexSet, to destination: Int) {
        var order = entries.map(\.id)
        order.move(fromOffsets: source, toOffset: destination)
        apply(order: order)
    }

    /// Sposta di una posizione, per chi preferisce la tastiera o non se la cava col drag.
    private func nudgeRow(_ entry: PlaylistEntry, by offset: Int) {
        var order = entries.map(\.id)
        guard let from = order.firstIndex(of: entry.id) else { return }
        let to = from + offset
        guard order.indices.contains(to) else { return }
        order.swapAt(from, to)
        apply(order: order)
    }

    private func apply(order: [String]) {
        // La lista si riordina subito e l'osservazione conferma un istante dopo: aspettare il
        // giro sul database farebbe tornare indietro la riga sotto il dito.
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })
        entries = order.compactMap { byID[$0] }
        model.reorderPlaylist(playlistID, orderedIDs: order)
    }

    private func deleteSelection() {
        guard !selection.isEmpty else { return }
        model.deleteItems(ids: selection, in: playlistID)
        selection = []
    }

    private func load(_ entry: PlaylistEntry, on slot: DeckState.Slot) {
        guard let track = entry.track else { return }
        model.load(track, on: slot)
    }

    private func commitRename() {
        let name = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let playlist, !name.isEmpty, name != playlist.name else { return }
        model.rename(playlist: playlist, to: name)
    }
}

/// Una riga di brano.
///
/// I due tastini **A** e **B** non sono un doppione del doppio clic: dentro un `List` con
/// selezione il clic va alla lista e i gesti sulla riga arrivano quando vogliono, mentre un
/// `Button` funziona sempre. Il doppio clic resta, come scorciatoia per chi lo prova per abitudine
/// venendo dalla libreria.
private struct PlaylistTrackRow: View {
    let entry: PlaylistEntry
    let number: Int?
    let deckBadge: String?
    let onLoad: (DeckState.Slot) -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(number.map(String.init) ?? "–")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .trailing)

            VStack(alignment: .leading, spacing: 1) {
                Text(entry.track?.title ?? "Traccia rimossa dalla libreria")
                    .lineLimit(1)
                    .foregroundStyle(entry.track == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
                if let artist = entry.track?.artist, !artist.isEmpty {
                    Text(artist)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if entry.track != nil {
                HStack(spacing: 3) {
                    loadButton(slot: .a, isLoaded: deckBadge == "A")
                    loadButton(slot: .b, isLoaded: deckBadge == "B")
                }
            }

            if let bpm = entry.track?.bpm {
                Text(String(format: "%.1f", bpm))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            if let duration = entry.track?.durationSeconds, duration > 0 {
                Text(Timecode.short(duration))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Il tasto è acceso quando quel deck ha già questa traccia.
    private func loadButton(slot: DeckState.Slot, isLoaded: Bool) -> some View {
        Button {
            onLoad(slot)
        } label: {
            Text(slot.rawValue)
                .font(.caption2.weight(.bold))
                .foregroundStyle(isLoaded ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .frame(width: 20, height: 16)
                .background(
                    isLoaded ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary),
                    in: RoundedRectangle(cornerRadius: 3)
                )
        }
        .buttonStyle(.plain)
        .help(isLoaded ? "Già sul deck \(slot.rawValue)" : "Carica sul deck \(slot.rawValue)")
    }
}

/// Una riga di nota, scrivibile sul posto.
///
/// **Non è un `TextField` sempre acceso**, e non per gusto: dentro un `List` con selezione il clic
/// viene preso dalla lista per selezionare la riga e il campo non riceve mai il fuoco — è il
/// motivo per cui le note non si potevano scrivere. Qui la nota a riposo è un `Button` (che il
/// clic lo riceve sempre); premendolo compare il campo, che si porta il fuoco addosso da sé e si
/// chiude con Invio o uscendo.
private struct PlaylistNoteRow: View {
    let item: PlaylistItem
    let onSave: (PlaylistItem) -> Void

    @State private var text: String = ""
    @State private var isEditing = false
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "text.quote")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 20, alignment: .trailing)

            if isEditing {
                TextField("Nota di passaggio", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .italic()
                    .lineLimit(1...4)
                    .focused($isFocused)
                    .onSubmit { commit() }
                    .onChange(of: isFocused) { _, focused in if !focused { commit() } }
                    .task { isFocused = true }
            } else {
                Button {
                    text = item.text
                    isEditing = true
                } label: {
                    Text(item.text.isEmpty ? "Nota di passaggio" : item.text)
                        .italic()
                        .foregroundStyle(item.text.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clic per scrivere la nota")
            }
        }
        .task(id: item.id) { text = item.text }
    }

    private func commit() {
        isEditing = false
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != item.text else { return }
        var updated = item
        updated.text = trimmed
        onSave(updated)
    }
}
