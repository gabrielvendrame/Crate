import SwiftUI
import DJKit

/// La libreria completa: tabella, ricerca e ispettore della traccia selezionata.
struct LibraryView: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    @State private var sortOrder = [KeyPathComparator(\Track.addedAt, order: .reverse)]

    /// Prima si filtra, poi si ordina: l'ordinamento è una faccenda della tabella, il filtro no —
    /// lo stesso sottoinsieme serve anche al conteggio e ai comandi di menu.
    private var sortedTracks: [Track] {
        model.filteredTracks.sorted(using: sortOrder)
    }

    var body: some View {
        @Bindable var model = model

        Group {
            if model.trackList.isEmpty {
                EmptyLibraryView { model.isImportSheetPresented = true }
            } else if sortedTracks.isEmpty {
                NoMatchesView(filter: model.libraryFilter) {
                    model.libraryFilter = LibraryFilter()
                }
            } else {
                table
            }
        }
        .navigationTitle("Libreria")
        .navigationSubtitle(subtitle)
        .searchable(
            text: $model.libraryFilter.text,
            placement: .toolbar,
            prompt: "Cerca per titolo, artista o album"
        )
        .toolbar {
            ToolbarItem(placement: .automatic) {
                scopePicker
            }
        }
        .inspector(isPresented: $model.isInspectorPresented) {
            Group {
                if let track = model.selectedTrack {
                    TrackInspector(track: track)
                } else {
                    ContentUnavailableView(
                        "Nessuna traccia selezionata",
                        systemImage: "sidebar.right",
                        description: Text("Seleziona un brano per modificarne i metadati e le foto dell'etichetta.")
                    )
                }
            }
            .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
        }
    }

    /// Quante tracce si stanno guardando, e su quante. Il secondo numero compare solo quando un
    /// filtro è attivo: senza filtro sarebbe due volte lo stesso.
    private var subtitle: String {
        let shown = sortedTracks.count
        let total = model.trackList.count
        if model.libraryFilter.isActive {
            return "\(shown) di \(total) brani"
        }
        return total == 1 ? "1 brano" : "\(total) brani"
    }

    private var scopePicker: some View {
        @Bindable var model = model

        return Picker("Filtro", selection: $model.libraryFilter.scope) {
            ForEach(LibraryFilter.Scope.allCases) { scope in
                Text(scope.label).tag(scope)
            }
        }
        .pickerStyle(.menu)
        .help("Mostra solo una parte della libreria")
    }

    private var table: some View {
        @Bindable var model = model

        return Table(of: Track.self, selection: $model.selectedTrackIDs, sortOrder: $sortOrder) {
            TableColumn("") { track in
                LabelThumbnail(track: track)
            }
            .width(28)

            TableColumn("Titolo", value: \.title) { track in
                Text(track.title.isEmpty ? track.youtubeID : track.title)
            }
            TableColumn("Artista", value: \.artist)
            TableColumn("Album", value: \.album)

            TableColumn("BPM") { track in
                Text(track.bpm.map { String(format: "%.1f", $0) } ?? "—")
                    .monospacedDigit()
                    .foregroundStyle(track.bpm == nil ? .secondary : .primary)
            }
            .width(60)

            TableColumn("Durata") { track in
                Text(Timecode.short(track.durationSeconds))
                    .monospacedDigit()
            }
            .width(70)

            TableColumn("Stato") { track in
                AnalysisStateBadge(
                    state: track.analysisState,
                    error: track.analysisError,
                    hasWaveform: track.peaksFilename != nil,
                    isAnalyzing: model.isAnalyzing(track)
                )
            }
            .width(130)
        } rows: {
            // Righe esplicite invece della forma breve `Table(sortedTracks, …)`: è il solo modo
            // di renderle trascinabili. Il payload è l'identificativo della traccia, che chi
            // riceve risolve contro la libreria.
            ForEach(sortedTracks) { track in
                TableRow(track)
                    .draggable(RowDrag(trackID: track.id))
            }
        }
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            rowMenu(for: ids)
        } primaryAction: { ids in
            // Doppio clic: sul deck A, che è quello da cui si parte sempre.
            if let track = track(in: ids) { model.load(track, on: .a) }
        }
        // ⌫ sulla selezione, come in ogni lista di macOS. Chiede conferma come tutto il resto.
        .onDeleteCommand {
            model.requestDeletion(of: model.selectedTrackIDs)
        }
    }

    private func track(in ids: Set<Track.ID>) -> Track? {
        guard ids.count == 1, let id = ids.first else { return nil }
        return model.trackList.first { $0.id == id }
    }

    /// Le tracce selezionate nell'ordine in cui compaiono in tabella: un `Set` non ha ordine, e
    /// aggiungendone tre a una scaletta l'ordine è proprio quello che conta.
    private func orderedTracks(in ids: Set<Track.ID>) -> [String] {
        sortedTracks.filter { ids.contains($0.id) }.map(\.id)
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<Track.ID>) -> some View {
        // Vale anche per una selezione multipla, e non dipende dal drag & drop: aggiungere venti
        // pezzi a una scaletta trascinandoli uno per uno non è un modo di lavorare.
        if !model.playlistList.isEmpty, !ids.isEmpty {
            Menu("Aggiungi alla scaletta") {
                ForEach(model.playlistList) { playlist in
                    Button(playlist.name) {
                        model.appendTracks(orderedTracks(in: ids), to: playlist.id)
                    }
                }
            }
            Divider()
        }

        if let track = track(in: ids) {
            Button("Carica sul deck A") { model.load(track, on: .a) }
            Button("Carica sul deck B") { model.load(track, on: .b) }
            Divider()
            Button("Rianalizza la traccia") { model.reanalyze(track) }
                .disabled(track.audioFilename == nil || model.isAnalyzing(track))
            Button("Cerca la copertina su Discogs") {
                model.findArtwork(for: track, showEvenIfSingle: true)
            }
            .disabled(!model.hasDiscogsToken || model.isSearchingArtwork(for: track))
            Divider()
        }

        if !ids.isEmpty {
            Button(
                ids.count == 1 ? "Elimina dalla libreria" : "Elimina \(ids.count) brani",
                role: .destructive
            ) {
                model.requestDeletion(of: ids)
            }
        }
    }
}

/// Miniatura dell'etichetta lato A: serve a riconoscere il disco a colpo d'occhio nella lista.
///
/// Il clic la apre a dimensione piena. Un pulsante dentro una cella di `Table` e non un
/// `onTapGesture`: il gesto si mangerebbe il clic della riga, e la selezione smetterebbe di
/// funzionare proprio sulla prima colonna — è lo stesso inciampo già visto sulle righe di `List`.
private struct LabelThumbnail: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    let track: Track

    var body: some View {
        if let filename = track.labelImageAFilename,
           let paths = model.paths,
           let image = NSImage(contentsOf: paths.artworkURL(filename: filename)) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 18, height: 18)
                .clipShape(Circle())
        } else {
            Circle()
                .fill(.quaternary)
                .frame(width: 18, height: 18)
        }
    }
}

private struct AnalysisStateBadge: View {
    let state: AnalysisState
    let error: String?
    let hasWaveform: Bool
    let isAnalyzing: Bool

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(tint)
            .help(error ?? text)
    }

    /// Una traccia importata prima che l'analisi esistesse risulta pronta ma non ha waveform:
    /// dirlo è l'unico modo perché si capisca che va ricalcolata.
    private var isMissingWaveform: Bool {
        state == .ready && !hasWaveform && !isAnalyzing
    }

    private var text: String {
        if isAnalyzing { return "Analizzo" }
        if isMissingWaveform { return "Senza waveform" }
        switch state {
        case .pending: return "In attesa"
        case .downloading: return "Scarico"
        case .analyzing: return "Analizzo"
        case .ready: return "Pronta"
        case .failed: return "Errore"
        }
    }

    private var symbol: String {
        if isAnalyzing { return "waveform" }
        if isMissingWaveform { return "waveform.slash" }
        switch state {
        case .pending: return "clock"
        case .downloading: return "arrow.down.circle"
        case .analyzing: return "waveform"
        case .ready: return "checkmark.circle"
        case .failed: return "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        if isAnalyzing { return .accentColor }
        if isMissingWaveform { return .orange }
        switch state {
        case .ready: return .secondary
        case .failed: return .red
        default: return .accentColor
        }
    }
}

/// Cosa si vede quando il filtro non lascia passare niente.
///
/// Separato dalla libreria vuota davvero, e non è pignoleria: sono due situazioni diverse e il
/// gesto che le risolve è opposto — lì si importa un brano, qui si toglie il filtro. Un unico
/// «nessun risultato» lascerebbe l'utente a chiedersi dove sono finiti i suoi dischi.
private struct NoMatchesView: View {
    let filter: LibraryFilter
    let onClear: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Nessun brano trovato", systemImage: "magnifyingglass")
        } description: {
            Text(description)
        } actions: {
            Button("Togli il filtro", action: onClear)
        }
    }

    private var description: String {
        let trimmed = filter.text.trimmingCharacters(in: .whitespaces)
        switch (trimmed.isEmpty, filter.scope) {
        case (true, let scope):
            return "Nessun brano nella selezione «\(scope.label)»."
        case (false, .all):
            return "Niente in libreria corrisponde a «\(trimmed)»."
        case (false, let scope):
            return "Niente corrisponde a «\(trimmed)» dentro «\(scope.label)»."
        }
    }
}

private struct EmptyLibraryView: View {
    let onImport: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Libreria vuota", systemImage: "music.note")
        } description: {
            Text("Incolla un link di YouTube per aggiungere il primo brano.")
        } actions: {
            Button("Aggiungi da YouTube", action: onImport)
                .buttonStyle(.borderedProminent)
        }
    }
}
