import SwiftUI
import DJKit

/// Il menu che mette e toglie i tag su una selezione di tracce.
///
/// Uno solo per due posti — il menu contestuale della tabella e l'ispettore — perché è lo stesso
/// gesto: la differenza fra «venti dischi selezionati» e «questo disco» è solo quante tracce ci
/// sono nell'insieme.
///
/// **Ogni voce è un interruttore, non un'aggiunta.** Con più tracce selezionate la spunta compare
/// quando ce l'hanno *tutte*, e premerla in quel caso toglie: è il comportamento di una casella a
/// tre stati, senza doverne disegnare una dentro un menu che non le sa mostrare.
struct TagMenu: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }

    let trackIDs: Set<String>
    /// Come si chiama il menu: «Tag» nel menu contestuale della tabella, dove sta fra altre voci;
    /// «Aggiungi un tag» nell'ispettore, dove è l'unico comando della sezione e deve dire da solo
    /// cosa fa.
    var title = "Tag"

    /// Chiamato dalla voce «Nuovo tag…»: il campo dove scriverne il nome non può stare dentro un
    /// menu, quindi lo apre chi il menu lo ospita.
    let onCreateNew: () -> Void

    var body: some View {
        Menu(title) {
            ForEach(model.tagList) { tag in
                Button {
                    model.toggleTag(tag, on: trackIDs)
                } label: {
                    Label {
                        Text(tag.name)
                    } icon: {
                        Image(systemName: isOn(tag) ? "checkmark.circle.fill" : "tag")
                            .foregroundStyle(CuePalette.color(at: tag.colorIndex))
                    }
                }
            }

            if !model.tagList.isEmpty { Divider() }

            Button("Nuovo tag…") { onCreateNew() }
        }
        .disabled(trackIDs.isEmpty)
    }

    private func isOn(_ tag: Tag) -> Bool {
        model.allTracks(trackIDs, have: tag)
    }
}
