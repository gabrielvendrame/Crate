import AppKit
import DJKit
import SwiftUI

/// Se la colonna sinistra del deck è stretta, cioè se i deck sono affiancati.
///
/// Passata dall'ambiente e non come parametro perché la leggono viste annidate a profondità
/// diverse — la colonna d'identità e la foto — e farla scendere a mano vorrebbe dire aggiungere
/// un argomento a ognuna.
private struct DeckIsNarrowKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var deckIsNarrow: Bool {
        get { self[DeckIsNarrowKey.self] }
        set { self[DeckIsNarrowKey.self] = newValue }
    }
}

/// La foto dell'etichetta del disco caricato, sotto il titolo, **piccola**.
///
/// Sta sul deck e non solo nell'ispettore perché è come il disco sul piatto: mentre si prova una
/// transizione si guarda il deck, e riconoscere il vinile a colpo d'occhio è metà del motivo per
/// cui le foto esistono. È piccola per scelta di Gabriel (2026-09-05) — la fascia dei deck deve
/// restare bassa — e il clic la apre a dimensione piena, che era l'obiettivo del task originale.
///
/// Mostra il **lato A**, e ricade sul B se il lato A manca: l'etichetta che si fotografa per prima
/// è quella del lato che si suona.
struct DeckLabelPhoto: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    @Environment(\.deckIsNarrow) private var isNarrow
    let track: Track

    @State private var isPreviewPresented = false

    private var side: VinylSide? {
        if track.labelImageAFilename != nil { return .a }
        if track.labelImageBFilename != nil { return .b }
        return nil
    }

    private var filename: String? {
        guard let side else { return nil }
        return side == .a ? track.labelImageAFilename : track.labelImageBFilename
    }

    private var image: NSImage? {
        guard let filename, let paths = model.paths else { return nil }
        return NSImage(contentsOf: paths.artworkURL(filename: filename))
    }

    private var size: CGFloat { isNarrow ? 34 : 44 }

    var body: some View {
        HStack(spacing: 6) {
            thumbnail
            if let side, !isNarrow {
                Text("Lato \(side.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image {
            Button { isPreviewPresented = true } label: {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))
            }
            .buttonStyle(.plain)
            .help("Clic per vedere l'etichetta a dimensione piena")
            .popover(isPresented: $isPreviewPresented, arrowEdge: .trailing) {
                LabelPreview(track: track)
            }
        } else {
            // Il posto della foto resta anche quando non c'è: senza, la colonna si accorcia
            // caricando una traccia senza etichetta e i comandi sotto ballano.
            Circle()
                .fill(.quaternary)
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: "photo")
                        .font(.system(size: size * 0.3))
                        .foregroundStyle(.tertiary)
                }
                .help("Nessuna foto dell'etichetta: trascinala nell'ispettore")
        }
    }
}

/// L'etichetta a dimensione piena, con i due lati se ci sono entrambi.
struct LabelPreview: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    let track: Track

    private var sides: [(VinylSide, NSImage)] {
        guard let paths = model.paths else { return [] }
        return VinylSide.allCases.compactMap { side in
            let filename = side == .a ? track.labelImageAFilename : track.labelImageBFilename
            guard let filename,
                  let image = NSImage(contentsOf: paths.artworkURL(filename: filename))
            else { return nil }
            return (side, image)
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Text(track.displayName)
                .font(.callout.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                ForEach(sides, id: \.0) { side, image in
                    VStack(spacing: 6) {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            // 420 punti: un'etichetta da 10 cm guardata come se fosse in mano.
                            // Più grande di così non aggiunge niente, perché la foto sorgente è
                            // salvata a 1200 px sul lato lungo.
                            .frame(maxWidth: 420, maxHeight: 420)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("Lato \(side.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: sides.count > 1 ? 900 : 470)
    }
}
