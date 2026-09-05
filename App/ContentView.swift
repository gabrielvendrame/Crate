import SwiftUI
import DJKit

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 340)
        } detail: {
            // **Non `VSplitView`.** È un `NSSplitView` e non propaga ai figli l'inset della
            // toolbar: il contenuto partiva dal bordo superiore della finestra e il titolo ci
            // finiva scritto sopra. Con una `VStack` il contenuto rispetta la toolbar, e
            // l'altezza dei deck è un numero nostro invece di una divisione che il framework
            // ricalcola ogni volta che cambia la vista sopra — che è come la fascia finiva
            // schiacciata al minimo entrando in una scaletta.
            VStack(spacing: 0) {
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                DeckBarDivider(height: $model.deckBarHeight)

                DeckBarView()
                    .frame(height: model.deckBarHeight)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Aggiungi da YouTube", systemImage: "plus") {
                    model.isImportSheetPresented = true
                }
                .help("Aggiungi un brano da un link di YouTube (⌘N)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Ispettore", systemImage: "sidebar.right") {
                    model.isInspectorPresented.toggle()
                }
                .help("Mostra o nascondi l'ispettore (⌥⌘I)")
            }
        }
        .sheet(isPresented: $model.isImportSheetPresented) {
            ImportSheet()
                .environment(model)
        }
        .alert(
            "Qualcosa non ha funzionato",
            isPresented: Binding(
                get: { model.transientError != nil },
                set: { if !$0 { model.transientError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { model.transientError = nil }
        } message: {
            Text(model.transientError ?? "")
        }
        .overlay {
            if let error = model.startupError {
                StartupErrorView(message: error)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        case .library, nil:
            LibraryView()
        case .playlist(let id):
            PlaylistDetailView(playlistID: id)
        }
    }
}

/// Se la libreria non si apre l'app non è utilizzabile: meglio dirlo con il motivo esatto.
private struct StartupErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
            Text("Impossibile aprire la libreria")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 480)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
