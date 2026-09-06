import SwiftUI
import DJKit

struct SidebarView: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }

    /// Il tag che si sta rinominando, e il nome in corso di scrittura. Un foglio d'avviso con un
    /// campo dentro, e non un campo modificabile sul posto: una `List` con selezione e drag &
    /// drop e per giunta un editor di testo nella riga è il modo più rapido di rompere tutti e
    /// tre — vedi l'inciampo dei gesti sulle righe già annotato altrove.
    @State private var renamingTag: Tag?
    @State private var isCreatingTag = false
    @State private var tagName = ""

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

            // Compare solo quando un tag c'è: chi non li usa non deve trovarsi una sezione vuota
            // in barra laterale. Il primo si crea dal pulsante in fondo, o dal menu contestuale
            // di un disco — che è il momento in cui viene voglia di averne uno.
            if !model.tagList.isEmpty {
                Section("Tag") {
                    ForEach(model.tagList) { tag in
                        tagRow(tag)
                    }
                    // Trascinandoli si riordinano: i due o tre che si usano di continuo stanno in
                    // cima, e l'ordine alfabetico non lo rispetterebbe.
                    .onMove { source, destination in
                        model.moveTags(fromOffsets: source, toOffset: destination)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                Button {
                    model.createPlaylist()
                } label: {
                    // `contentShape` e non solo la `Label`: con `.plain` il bersaglio del clic è
                    // **quello che si vede disegnato**, quindi lo spazio fra l'icona e la parola
                    // non risponde. Provando l'app il clic ci cadeva in mezzo e non succedeva
                    // niente — un pulsante che a volte funziona e a volte no.
                    Label("Nuova scaletta", systemImage: "plus")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer(minLength: 0)

                Button {
                    tagName = ""
                    isCreatingTag = true
                } label: {
                    Label("Tag", systemImage: "tag")
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Crea un tag: un'etichetta tua per ritrovare i dischi in cassa")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .alert("Nuovo tag", isPresented: $isCreatingTag) {
            TextField("Nome", text: $tagName)
            // **Nessun `disabled` legato a quello che si sta scrivendo.** Il contenuto di un
            // `.alert` su macOS viene costruito quando l'avviso compare e non si rivaluta: un
            // pulsante disabilitato sul campo vuoto resta disabilitato anche dopo aver scritto il
            // nome, e l'avviso si chiude senza aver fatto niente. Visto provando l'app. Il nome
            // vuoto lo scarta l'azione, che invece lo stato corrente ce l'ha.
            Button("Crea") {
                guard Tag.normalized(name: tagName) != nil else { return }
                model.createTag(named: tagName)
            }
            Button("Annulla", role: .cancel) {}
        } message: {
            Text("Un'etichetta tua — «disco», «funky» — per ritrovare i dischi in cassa.")
        }
        .alert("Rinomina il tag", isPresented: renamingBinding) {
            TextField("Nome", text: $tagName)
            Button("Rinomina") {
                guard let renamingTag, Tag.normalized(name: tagName) != nil else { return }
                model.rename(renamingTag, to: tagName)
            }
            Button("Annulla", role: .cancel) {}
        }
    }

    private var renamingBinding: Binding<Bool> {
        Binding(
            get: { renamingTag != nil },
            set: { if !$0 { renamingTag = nil } }
        )
    }

    private func tagRow(_ tag: Tag) -> some View {
        Label {
            Text(tag.name)
        } icon: {
            Image(systemName: "tag.fill")
                .foregroundStyle(CuePalette.color(at: tag.colorIndex))
        }
        .badge(model.trackCount(for: tag))
        .tag(SidebarSelection.tag(tag.id))
        // Trascinare dei dischi su un tag glielo mette, come trascinarli su una scaletta ce li
        // aggiunge: è lo stesso gesto per la stessa domanda — «questi vanno lì».
        .dropDestination(for: RowDrag.self) { drags, _ in
            let ids = Set(drags.compactMap(\.trackID))
            guard !ids.isEmpty else { return false }
            model.toggleTag(tag, on: ids)
            return true
        }
        .contextMenu {
            Button("Rinomina…") {
                tagName = tag.name
                renamingTag = tag
            }
            Menu("Colore") {
                ForEach(CuePalette.rgb.indices, id: \.self) { index in
                    Button {
                        model.setColorIndex(index, for: tag)
                    } label: {
                        Label {
                            Text(CuePalette.name(at: index))
                        } icon: {
                            Image(systemName: index == tag.colorIndex ? "checkmark.circle.fill" : "circle.fill")
                                .foregroundStyle(CuePalette.color(at: index))
                        }
                    }
                }
            }
            Divider()
            Button("Elimina il tag", role: .destructive) { model.deleteTag(tag) }
        }
    }
}
