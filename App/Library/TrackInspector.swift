import AppKit
import SwiftUI
import DJKit

/// Ispettore della traccia selezionata: i tre campi di metadati e le foto delle due etichette.
///
/// I campi si salvano da soli poco dopo che si smette di scrivere: non c'è un pulsante "Salva"
/// perché correggere un titolo sbagliato dal parsing è un gesto che si ripete di continuo.
struct TrackInspector: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    let track: Track

    @State private var title = ""
    @State private var artist = ""
    @State private var album = ""
    @State private var bpm = ""
    @State private var saveTask: Task<Void, Never>?
    /// La versione della traccia da cui i campi sono stati riempiti l'ultima volta. Serve a
    /// distinguere «questo campo non l'ha toccato nessuno» da «lo sta scrivendo adesso».
    @State private var loaded: Track?
    @State private var isCreatingTag = false
    @State private var newTagName = ""

    var body: some View {
        Form {
            Section("Metadati") {
                TextField("Titolo", text: $title)
                TextField("Artista", text: $artist)
                TextField("Album", text: $album)
            }

            // Sotto i metadati e sopra l'etichetta: i tag sono la quinta cosa che si guarda di
            // un disco, dopo i quattro campi, e sono l'unico posto dove si scrive qualcosa che
            // non viene né da YouTube né da Discogs.
            Section("Tag") {
                ForEach(model.tags(of: track)) { tag in
                    HStack(spacing: 6) {
                        Image(systemName: "tag.fill")
                            .foregroundStyle(CuePalette.color(at: tag.colorIndex))
                        Text(tag.name)
                        Spacer(minLength: 0)
                        Button {
                            model.toggleTag(tag, on: [track.id])
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                        .help("Togli «\(tag.name)» da questo brano")
                    }
                }

                TagMenu(trackIDs: [track.id], title: "Aggiungi un tag") {
                    newTagName = ""
                    isCreatingTag = true
                }
            }

            Section("Etichetta") {
                HStack(spacing: 12) {
                    LabelPhotoWell(track: track, side: .a)
                    LabelPhotoWell(track: track, side: .b)
                }
                .frame(maxWidth: .infinity)

                Button {
                    model.findArtwork(for: track, showEvenIfSingle: true)
                } label: {
                    if model.isSearchingArtwork(for: track) {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.small)
                            Text("Cerco su Discogs…")
                        }
                    } else {
                        Label("Cerca la copertina su Discogs", systemImage: "magnifyingglass")
                    }
                }
                .disabled(!model.hasDiscogsToken || model.isSearchingArtwork(for: track))
                .help(model.hasDiscogsToken
                    ? "Mostra le edizioni che Discogs conosce e scegline la copertina"
                    : "Serve il token di Discogs: mettilo nelle impostazioni (⌘,)")
            }

            Section("Dettagli") {
                LabeledContent("Durata", value: Self.duration(track.durationSeconds))
                // Il BPM si corregge anche da qui, non solo dall'editor della griglia sul deck:
                // capita di accorgersi che è sbagliato guardando la tabella, prima di aver
                // caricato la traccia da qualche parte. Il downbeat invece si tocca solo sul
                // deck, dove si vede la waveform sotto le battute.
                LabeledContent("BPM") {
                    HStack(spacing: 6) {
                        // Dentro un `Form` la stringa di un `TextField` diventa un'etichetta a
                        // sinistra del campo, non un segnaposto: qui accanto a "BPM" comparivano
                        // due etichette. Il testo di suggerimento va passato come `prompt`.
                        TextField("", text: $bpm, prompt: Text("non rilevato"))
                            .labelsHidden()
                            .help("Scrivi il tempo e premi Invio · vuoto toglie la griglia")
                            .frame(width: 70)
                            .monospacedDigit()
                            .multilineTextAlignment(.trailing)
                            .onSubmit { commitBPM() }
                        Button("Rileva") { model.reanalyze(track) }
                            .controlSize(.small)
                            .disabled(model.isAnalyzing(track) || track.audioFilename == nil)
                    }
                }
                LabeledContent("Audio", value: "\(Int(track.sampleRate)) Hz · \(track.channelCount) canali")
                LabeledContent("Origine") {
                    Link("YouTube", destination: URL(string: track.youtubeURL) ?? URL(string: "https://youtube.com")!)
                }
                if let error = track.analysisError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section {
                Button("Elimina dalla libreria", role: .destructive) {
                    model.requestDeletion(of: track)
                }
            }
        }
        .formStyle(.grouped)
        .alert("Nuovo tag", isPresented: $isCreatingTag) {
            TextField("Nome", text: $newTagName)
            Button("Crea e assegna") {
                guard Tag.normalized(name: newTagName) != nil else { return }
                model.createTag(named: newTagName, andAssignTo: [track.id])
            }
            Button("Annulla", role: .cancel) {}
        }
        .task(id: track.id) { load() }
        // La riga può cambiare **da fuori** mentre è sotto gli occhi: scegliendo l'edizione su
        // Discogs arriva il nome dell'album, e l'analisi porta il BPM. Senza questo i campi
        // restavano quelli di quando la traccia è stata selezionata — e alla prima correzione di
        // un altro campo il salvataggio avrebbe riscritto sopra l'album appena arrivato, perché
        // scrive tutti e tre insieme.
        .onChange(of: track) { _, updated in merge(updated) }
        .onChange(of: title) { scheduleSave() }
        .onChange(of: artist) { scheduleSave() }
        .onChange(of: album) { scheduleSave() }
    }

    private func load() {
        saveTask?.cancel()
        loaded = track
        title = track.title
        artist = track.artist
        album = track.album
        bpm = Self.formatted(track.bpm)
    }

    /// Porta nei campi ciò che è cambiato in tabella, **lasciando stare quelli che si stanno
    /// scrivendo**: un campo il cui testo è ancora quello caricato non l'ha toccato nessuno e si
    /// può aggiornare; uno diverso è lavoro dell'utente e ricaricarlo glielo cancellerebbe sotto
    /// le dita.
    private func merge(_ updated: Track) {
        guard let previous = loaded else {
            load()
            return
        }
        if title == previous.title { title = updated.title }
        if artist == previous.artist { artist = updated.artist }
        if album == previous.album { album = updated.album }
        if bpm == Self.formatted(previous.bpm) { bpm = Self.formatted(updated.bpm) }
        loaded = updated
    }

    private static func formatted(_ bpm: Double?) -> String {
        bpm.map { String(format: "%.2f", $0) } ?? ""
    }

    /// Il campo vuoto toglie la griglia; un numero storto si rifiuta rimettendo quello di prima,
    /// invece di scrivere in tabella qualcosa che il quantize prenderebbe per buono.
    private func commitBPM() {
        let trimmed = bpm.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            model.setBPM(nil, for: track)
            return
        }
        guard let value = Double(trimmed.replacingOccurrences(of: ",", with: ".")),
              DeckState.bpmRange.contains(value)
        else {
            bpm = Self.formatted(track.bpm)
            return
        }
        model.setBPM(value, for: track)
    }

    /// Salvataggio ritardato: si scrive sul database quando la digitazione si ferma, non a ogni
    /// tasto premuto.
    private func scheduleSave() {
        guard title != track.title || artist != track.artist || album != track.album else { return }
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            var updated = track
            updated.title = title
            updated.artist = artist
            updated.album = album
            model.save(track: updated)
        }
    }

    private static func duration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Riquadro per la foto di un lato del disco: accetta un file trascinato dal Finder oppure
/// un'immagine incollata dagli appunti.
private struct LabelPhotoWell: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    let track: Track
    let side: VinylSide

    @State private var isTargeted = false
    @State private var isCameraPresented = false

    private var filename: String? {
        side == .a ? track.labelImageAFilename : track.labelImageBFilename
    }

    private var image: NSImage? {
        guard let filename, let paths = model.paths else { return nil }
        return NSImage(contentsOf: paths.artworkURL(filename: filename))
    }

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(isTargeted ? Color.accentColor : Color.clear, lineWidth: 2)

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
                    VStack(spacing: 4) {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                        Text("trascina, incolla\no scatta")
                            .font(.caption2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .frame(height: 110)
            .contentShape(RoundedRectangle(cornerRadius: 6))
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first else { return false }
                model.setLabelImage(contentsOf: url, side: side, for: track)
                return true
            } isTargeted: { isTargeted = $0 }
            .contextMenu {
                Button("Scatta una foto…") { isCameraPresented = true }
                Button("Scegli un file…") { chooseFile() }
                Button("Incolla immagine") {
                    model.setLabelImageFromPasteboard(side: side, for: track)
                }
                if filename != nil {
                    Divider()
                    Button("Rimuovi", role: .destructive) {
                        model.removeLabelImage(side: side, for: track)
                    }
                }
            }
            .onTapGesture(count: 2) { chooseFile() }
            .sheet(isPresented: $isCameraPresented) {
                LabelCameraSheet(track: track, side: side)
            }

            HStack(spacing: 6) {
                Text("Lato \(side.rawValue)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    isCameraPresented = true
                } label: {
                    Image(systemName: "camera")
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Scatta la foto dell'etichetta con la fotocamera o con l'iPhone")
            }
        }
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = "Usa questa foto"
        if panel.runModal() == .OK, let url = panel.url {
            model.setLabelImage(contentsOf: url, side: side, for: track)
        }
    }
}
