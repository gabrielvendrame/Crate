import SwiftUI

@main
struct CrateApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
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

                Button("Ricalcola la waveform") {
                    if let track = model.selectedTrack { model.reanalyze(track) }
                }
                .keyboardShortcut("r", modifiers: [.command, .option])
                .disabled(model.selectedTrack?.audioFilename == nil)

                Button("Calcola le waveform mancanti") {
                    model.analyzeTracksWithoutWaveform()
                }
                .disabled(model.tracksWithoutWaveform.isEmpty)
            }
        }
    }
}
