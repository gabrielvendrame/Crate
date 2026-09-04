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
