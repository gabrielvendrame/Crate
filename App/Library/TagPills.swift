import DJKit
import SwiftUI

/// I tag di una traccia, come pastiglie colorate.
///
/// Uno solo per la colonna della libreria e per le righe di scaletta: sono la stessa
/// informazione nello stesso linguaggio visivo, e sdoppiarlo avrebbe voluto dire due posti dove
/// aggiustare la stessa cosa.
///
/// **Il nome ci sta dentro, non solo il colore.** Un pallino colorato è illeggibile appena i tag
/// passano i tre o quattro: il colore serve a riconoscerli con la coda dell'occhio, il nome a
/// sapere quale sia. Se non ci sta per larghezza, la riga si tronca — e il tooltip li elenca
/// tutti.
struct TagPills: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }

    let track: Track
    /// Quanto piccolo scriverli: nella tabella stanno su una riga di 26 punti, in scaletta
    /// accanto all'artista.
    var compact = false

    private var tags: [Tag] { model.tags(of: track) }

    var body: some View {
        if !tags.isEmpty {
            HStack(spacing: 3) {
                ForEach(tags) { tag in
                    Text(tag.name)
                        .font(compact ? .system(size: 9) : .caption2)
                        .lineLimit(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, compact ? 0.5 : 1.5)
                        .background(
                            CuePalette.color(at: tag.colorIndex).opacity(0.22),
                            in: Capsule()
                        )
                        .overlay(
                            Capsule().strokeBorder(
                                CuePalette.color(at: tag.colorIndex).opacity(0.55),
                                lineWidth: 0.5
                            )
                        )
                        .foregroundStyle(CuePalette.color(at: tag.colorIndex))
                }
            }
            .help(tags.map(\.name).joined(separator: " · "))
        }
    }
}
