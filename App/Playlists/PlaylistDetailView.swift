import SwiftUI
import DJKit

/// Editor di una scaletta. In M1 mostra solo intestazione e righe in sola lettura;
/// drag & drop, note inseribili e caricamento sui deck arrivano in M5.
struct PlaylistDetailView: View {
    @Environment(AppModel.self) private var model
    let playlistID: String

    @State private var entries: [PlaylistEntry] = []

    private var playlist: Playlist? {
        model.playlistList.first { $0.id == playlistID }
    }

    var body: some View {
        Group {
            if entries.isEmpty {
                ContentUnavailableView {
                    Label("Scaletta vuota", systemImage: "list.bullet.rectangle")
                } description: {
                    Text("Trascina qui i brani dalla libreria.")
                }
            } else {
                List(entries) { entry in
                    PlaylistRow(entry: entry)
                }
            }
        }
        .navigationTitle(playlist?.name ?? "Scaletta")
        .task(id: playlistID) { await reload() }
    }

    private func reload() async {
        guard let playlists = model.playlists else { return }
        entries = (try? await playlists.entries(playlistID: playlistID)) ?? []
    }
}

private struct PlaylistRow: View {
    let entry: PlaylistEntry

    var body: some View {
        switch entry.item.kind {
        case .track:
            HStack {
                Image(systemName: "music.note")
                    .foregroundStyle(.secondary)
                Text(entry.track?.displayName ?? "Traccia rimossa dalla libreria")
                    .foregroundStyle(entry.track == nil ? .secondary : .primary)
                Spacer()
                if let bpm = entry.track?.bpm {
                    Text(String(format: "%.1f", bpm))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
        case .note:
            HStack(alignment: .top) {
                Image(systemName: "text.quote")
                    .foregroundStyle(.tertiary)
                Text(entry.item.text.isEmpty ? "Nota vuota" : entry.item.text)
                    .italic()
                    .foregroundStyle(.secondary)
            }
            .padding(.leading, 16)
        }
    }
}
