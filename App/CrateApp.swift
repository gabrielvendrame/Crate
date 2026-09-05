import DJKit
import SwiftUI

@main
struct CrateApp: App {
    private var model: AppModel { .shared }

    /// I comandi di menu non possono usare `@Bindable`, che vive dentro un `body` di vista: i
    /// due binding si costruiscono a mano sul modello.
    private var quantizeBinding: Binding<Bool> {
        Binding(get: { model.isQuantizeEnabled }, set: { model.isQuantizeEnabled = $0 })
    }

    private var resolutionBinding: Binding<QuantizeResolution> {
        Binding(get: { model.quantizeResolution }, set: { model.quantizeResolution = $0 })
    }

    private var layoutBinding: Binding<AppModel.DeckLayout> {
        Binding(get: { model.deckLayout }, set: { model.deckLayout = $0 })
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1100, minHeight: 720)
        }
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Aggiungi da YouTube…") { model.isImportSheetPresented = true }
                    .keyboardShortcut("n", modifiers: .command)
                Button("Nuova scaletta") { model.createPlaylist() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(after: .sidebar) {
                Button("Mostra ispettore") { model.isInspectorPresented.toggle() }
                    .keyboardShortcut("i", modifiers: [.command, .option])

                Picker("Disposizione dei deck", selection: layoutBinding) {
                    ForEach(AppModel.DeckLayout.allCases, id: \.self) { layout in
                        Text(layout.label).tag(layout)
                    }
                }

                Button("Cambia disposizione dei deck") { model.toggleDeckLayout() }
                    .keyboardShortcut("d", modifiers: [.command, .option])

                Divider()
            }
            CommandMenu("Deck") {
                Button("Carica sul deck A") {
                    if let track = model.selectedTrack { model.load(track, on: .a) }
                }
                .keyboardShortcut("1", modifiers: .command)
                .disabled(model.selectedTrack == nil)

                Button("Carica sul deck B") {
                    if let track = model.selectedTrack { model.load(track, on: .b) }
                }
                .keyboardShortcut("2", modifiers: .command)
                .disabled(model.selectedTrack == nil)

                Divider()

                // Waveform e BPM escono dalla stessa passata di analisi: due comandi separati
                // vorrebbero dire decodificare due volte lo stesso file.
                Button("Rianalizza la traccia") {
                    if let track = model.selectedTrack { model.reanalyze(track) }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(model.selectedTrack?.audioFilename == nil)

                Button("Analizza le tracce mancanti") {
                    model.analyzeTracksWithoutAnalysis()
                }
                .disabled(model.tracksWithoutAnalysis.isEmpty)

                Divider()

                Toggle("Quantize", isOn: quantizeBinding)
                    .keyboardShortcut("q", modifiers: [.command, .option])

                Picker("Aggancio del quantize", selection: resolutionBinding) {
                    ForEach(QuantizeResolution.allCases, id: \.self) { resolution in
                        Text(resolution.label).tag(resolution)
                    }
                }
                .disabled(!model.isQuantizeEnabled)

                Divider()

                Button("Passa all'altro deck") { model.toggleFocusedDeck() }
                    .keyboardShortcut("d", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .appSettings) {
                Button("Impostazioni…") { model.isSettingsSheetPresented = true }
                    .keyboardShortcut(",", modifiers: .command)
            }

            CommandGroup(replacing: .help) {
                Button("Scorciatoie da tastiera") { model.isShortcutsSheetPresented = true }
                    .keyboardShortcut("/", modifiers: .command)
            }
        }
    }
}
