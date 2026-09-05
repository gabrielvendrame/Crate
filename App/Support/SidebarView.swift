import SwiftUI
import DJKit

struct SidebarView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        List(selection: $model.selection) {
            Section {
                Label("Libreria", systemImage: "music.note.list")
                    .badge(model.trackList.count)
                    .tag(SidebarSelection.library)
            }

            Section("Scalette") {
                ForEach(model.playlistList) { playlist in
                    Label(playlist.name, systemImage: "list.bullet.rectangle")
                        .tag(SidebarSelection.playlist(playlist.id))
                        // **È qui che si aggiungono i brani trascinandoli.** Libreria ed editor
                        // di scaletta sono due viste alternative dello stesso pannello: mentre
                        // guardi la libreria la scaletta non è sullo schermo, quindi l'unico
                        // posto dove si può lasciar cadere un brano è la sua riga qui a lato —
                        // come in Musica. Il drop dentro l'editor serve solo a riordinare.
                        .dropDestination(for: RowDrag.self) { drags, _ in
                            let ids = model.trackList
                                .filter { track in drags.contains { $0.trackID == track.id } }
                                .map(\.id)
                            guard !ids.isEmpty else { return false }
                            model.appendTracks(ids, to: playlist.id)
                            return true
                        }
                        .contextMenu {
                            Button("Elimina", role: .destructive) {
                                model.deletePlaylist(id: playlist.id)
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                model.createPlaylist()
            } label: {
                Label("Nuova scaletta", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }
}
