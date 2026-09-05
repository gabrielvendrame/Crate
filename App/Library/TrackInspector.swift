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

    var body: some View {
        Form {
            Section("Metadati") {
                TextField("Titolo", text: $title)
                TextField("Artista", text: $artist)
                TextField("Album", text: $album)
            }

            Section("Etichetta") {
                HStack(spacing: 12) {
                    LabelPhotoWell(track: track, side: .a)
                    LabelPhotoWell(track: track, side: .b)
                }
                .frame(maxWidth: .infinity)
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
        .task(id: track.id) { load() }
        .onChange(of: title) { scheduleSave() }
        .onChange(of: artist) { scheduleSave() }
        .onChange(of: album) { scheduleSave() }
    }

    private func load() {
        saveTask?.cancel()
        title = track.title
        artist = track.artist
        album = track.album
        bpm = track.bpm.map { String(format: "%.2f", $0) } ?? ""
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
            bpm = track.bpm.map { String(format: "%.2f", $0) } ?? ""
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
                        Text("trascina o incolla")
                            .font(.caption2)
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
                Button("Incolla immagine") {
                    model.setLabelImageFromPasteboard(side: side, for: track)
                }
                if filename != nil {
                    Button("Rimuovi", role: .destructive) {
                        model.removeLabelImage(side: side, for: track)
                    }
                }
            }
            .onTapGesture(count: 2) { chooseFile() }

            Text("Lato \(side.rawValue)")
                .font(.caption)
                .foregroundStyle(.secondary)
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
