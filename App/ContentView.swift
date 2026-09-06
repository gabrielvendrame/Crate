import SwiftUI
import DJKit

struct ContentView: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }

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

                // **Altezza esatta, ma mai sotto quella che il contenuto ha dichiarato.**
                //
                // Esatta perché la fascia deve stare dove la si è messa trascinando: lasciandola
                // elastica (`minHeight`) si prende tutto lo spazio libero e il trascinamento non
                // fa più niente. Mai sotto il pavimento perché un contenuto più alto della
                // cornice non si comprime — deborda **centrato**, quindi tagliato sotto dal bordo
                // della finestra e sopra sopra la maniglia, che sembrava sparita. Il pavimento lo
                // misura la fascia stessa: vedi `AppModel.deckBarContentFloor`.
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
            // Solo dove un ispettore c'è: dentro una scaletta il pulsante non aveva niente da
            // aprire e restava lì a non fare nulla.
            if model.showsInspector {
                ToolbarItem(placement: .primaryAction) {
                    Button("Ispettore", systemImage: "sidebar.right") {
                        model.isInspectorPresented.toggle()
                    }
                    .help("Mostra o nascondi l'ispettore (⌥⌘I)")
                }
            }
        }
        .sheet(isPresented: $model.isImportSheetPresented) {
            ImportSheet()
        }
        .sheet(isPresented: $model.isSettingsSheetPresented) {
            SettingsSheet()
        }
        // La scelta della copertina: una traccia per volta, dalla coda. Chiudere il foglio toglie
        // quella scelta dalla coda e fa salire la successiva.
        .sheet(item: Binding(
            get: { model.artworkChoices.first },
            set: { if $0 == nil, let first = model.artworkChoices.first {
                model.dismissArtworkChoice(for: first.track)
            } }
        )) { choice in
            DiscogsPickerSheet(choice: choice)
        }
        .sheet(isPresented: $model.isShortcutsSheetPresented) {
            ShortcutsSheet()
        }
        .confirmationDialog(
            deletionTitle,
            isPresented: Binding(
                get: { !model.pendingDeletion.isEmpty },
                set: { if !$0 { model.pendingDeletion = [] } }
            ),
            titleVisibility: .visible
        ) {
            Button("Elimina", role: .destructive) { model.confirmPendingDeletion() }
            Button("Annulla", role: .cancel) { model.pendingDeletion = [] }
        } message: {
            Text(deletionMessage)
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

    /// **L'eliminazione si conferma sempre**, anche per una traccia sola: porta via un file audio
    /// che è costato minuti di download, sparisce dal disco e non c'è un annulla. Il messaggio
    /// dice cosa va via e quanto spazio libera — che è il numero che fa decidere.
    private var deletionTitle: String {
        switch model.pendingDeletion.count {
        case 0: "Eliminare?"
        case 1: "Eliminare «\(model.pendingDeletion[0].displayName)»?"
        case let count: "Eliminare \(count) brani?"
        }
    }

    private var deletionMessage: String {
        let bytes = model.pendingDeletionBytes
        let size = bytes > 0
            ? ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
            : nil

        var lines = ["Spariscono l'audio scaricato, la waveform, i cue point e le foto dell'etichetta."]
        if model.pendingDeletion.count > 1 {
            lines.append(model.pendingDeletion.prefix(6).map(\.displayName).joined(separator: "\n"))
            if model.pendingDeletion.count > 6 {
                lines.append("…e altri \(model.pendingDeletion.count - 6).")
            }
        }
        if let size { lines.append("Libera \(size). Non si può annullare.") }
        else { lines.append("Non si può annullare.") }
        return lines.joined(separator: "\n\n")
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selection {
        // Un tag è la libreria vista da lì: stessa tabella, stesso ispettore, stessa ricerca —
        // solo meno righe. Una vista a parte non avrebbe niente di diverso da dire.
        case .library, .tag, nil:
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
