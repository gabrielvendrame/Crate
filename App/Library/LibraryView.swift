import SwiftUI
import DJKit

/// La libreria completa: tabella, ricerca e ispettore della traccia selezionata.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\Track.addedAt, order: .reverse)]

    private var sortedTracks: [Track] {
        model.trackList.sorted(using: sortOrder)
    }

    var body: some View {
        @Bindable var model = model

        Group {
            if model.trackList.isEmpty {
                EmptyLibraryView { model.isImportSheetPresented = true }
            } else {
                table
            }
        }
        .navigationTitle("Libreria")
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

    private var table: some View {
        @Bindable var model = model

        return Table(sortedTracks, selection: $model.selectedTrackIDs, sortOrder: $sortOrder) {
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
                Text(Self.duration(track.durationSeconds))
                    .monospacedDigit()
            }
            .width(70)

            TableColumn("Stato") { track in
                AnalysisStateBadge(state: track.analysisState, error: track.analysisError)
            }
            .width(110)
        }
        .contextMenu(forSelectionType: Track.ID.self) { ids in
            if ids.count == 1, let track = model.trackList.first(where: { $0.id == ids.first }) {
                Button("Elimina dalla libreria", role: .destructive) {
                    model.deleteTrack(track)
                }
            }
        }
    }

    private static func duration(_ seconds: Double) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Miniatura dell'etichetta lato A: serve a riconoscere il disco a colpo d'occhio nella lista.
private struct LabelThumbnail: View {
    @Environment(AppModel.self) private var model
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

    var body: some View {
        Label(text, systemImage: symbol)
            .font(.caption)
            .foregroundStyle(tint)
            .help(error ?? text)
    }

    private var text: String {
        switch state {
        case .pending: "In attesa"
        case .downloading: "Scarico"
        case .analyzing: "Analizzo"
        case .ready: "Pronta"
        case .failed: "Errore"
        }
    }

    private var symbol: String {
        switch state {
        case .pending: "clock"
        case .downloading: "arrow.down.circle"
        case .analyzing: "waveform"
        case .ready: "checkmark.circle"
        case .failed: "exclamationmark.triangle"
        }
    }

    private var tint: Color {
        switch state {
        case .ready: .secondary
        case .failed: .red
        default: .accentColor
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
