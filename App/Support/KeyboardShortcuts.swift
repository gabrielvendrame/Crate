import SwiftUI

/// L'elenco delle scorciatoie, in un posto solo.
///
/// **La stessa tabella alimenta il pannello di aiuto e nient'altro**: le scorciatoie vere stanno
/// dove devono stare — quelle con modificatori nei menu, quelle a tasto nudo in `DeckKeyMonitor` —
/// e questa è la loro documentazione. Tenerla accanto al codice che le implementa è l'unico modo
/// perché non divergano, ed è per questo che i due file si citano a vicenda.
enum KeyboardShortcuts {
    struct Entry: Identifiable {
        let keys: String
        let what: String
        var id: String { keys + what }
    }

    struct Group: Identifiable {
        let title: String
        let entries: [Entry]
        var id: String { title }
    }

    static let groups: [Group] = [
        Group(title: "Deck", entries: [
            Entry(keys: "Spazio", what: "Riproduci o metti in pausa il deck attivo"),
            Entry(keys: "C", what: "CUE — tenuto premuto in pausa sul cue fa l'anteprima"),
            Entry(keys: "Z · X", what: "Nudge indietro e avanti · tenuti, spingono di ±3%"),
            Entry(keys: "D", what: "Passa il fuoco all'altro deck"),
            Entry(keys: "1 – 8", what: "Hot cue: pad vuoto memorizza, pad pieno salta e suona"),
            Entry(keys: "⇧1 – ⇧8", what: "Cancella l'hot cue di quello slot"),
            Entry(keys: "⌘1 · ⌘2", what: "Carica il brano selezionato sul deck A o B"),
            Entry(keys: "− · +", what: "Allarga o stringe la vista zoomata della waveform"),
        ]),
        Group(title: "Griglia e quantize", entries: [
            Entry(keys: "⌥⌘Q", what: "Accende e spegne il quantize"),
            Entry(keys: "G", what: "Apre l'editor della griglia del deck attivo"),
            Entry(keys: "⌥ e trascina", what: "Sposta la griglia sulla waveform zoomata"),
            Entry(keys: "⌥⌘R", what: "Rianalizza la traccia selezionata: waveform e BPM"),
        ]),
        Group(title: "Libreria e scalette", entries: [
            Entry(keys: "⌘N", what: "Aggiungi un brano da un link di YouTube"),
            Entry(keys: "⇧⌘N", what: "Nuova scaletta"),
            Entry(keys: "⌘F", what: "Cerca in libreria"),
            Entry(keys: "⌫", what: "Elimina la selezione, con conferma"),
            Entry(keys: "⌥⌘I", what: "Mostra o nasconde l'ispettore"),
            Entry(keys: "Doppio clic", what: "Carica il brano sul deck A"),
        ]),
        Group(title: "Finestra", entries: [
            Entry(keys: "⌥⌘D", what: "Deck impilati o affiancati"),
            Entry(keys: "⇧⌘D", what: "Passa all'altro deck"),
            Entry(keys: "⌘,", what: "Impostazioni: token di Discogs e aggiornamento di yt-dlp"),
            Entry(keys: "⌘/", what: "Questo pannello"),
        ]),
    ]
}

/// Il pannello di aiuto: tutte le scorciatoie, in colonne.
struct ShortcutsSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Scorciatoie da tastiera")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(KeyboardShortcuts.groups) { group in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(group.title)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(group.entries) { entry in
                                HStack(alignment: .firstTextBaseline, spacing: 12) {
                                    Text(entry.keys)
                                        .font(.callout.monospaced())
                                        .frame(width: 116, alignment: .trailing)
                                        .foregroundStyle(.primary)
                                    Text(entry.what)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                        }
                    }

                    Text("I tasti senza modificatori valgono solo quando non stai scrivendo in un campo e non c'è un foglio aperto.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(20)
            }
        }
        .frame(width: 560, height: 560)
    }
}
