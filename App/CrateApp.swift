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
        }
    }
}
