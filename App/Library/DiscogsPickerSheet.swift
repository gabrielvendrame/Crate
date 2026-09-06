import AppKit
import DJKit
import SwiftUI

/// Scelta della copertina fra le edizioni che Discogs conosce.
///
/// Le copertine si guardano, non si leggono: la griglia mette le immagini grandi abbastanza da
/// riconoscere il disco, e il testo sotto serve solo a distinguere due ristampe — etichetta,
/// numero di catalogo, anno, paese, formato.
///
/// **Le edizioni in vinile vengono per prime.** Questa app prepara set da suonare sui piatti: fra
/// una ristampa digitale e il 12" originale, quello che si vuole in libreria è il secondo.
struct DiscogsPickerSheet: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    @Environment(\.dismiss) private var dismiss

    let choice: AppModel.ArtworkChoice

    @State private var isApplying = false

    private var releases: [DiscogsRelease] {
        choice.releases.sorted { first, second in
            first.isVinyl && !second.isVinyl
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 150, maximum: 190), spacing: 14)]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            ScrollView {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(releases) { release in
                        ReleaseCell(release: release) { choose(release) }
                            .disabled(isApplying)
                    }
                }
                .padding(16)
            }

            Divider()
            footer
        }
        .frame(width: 720, height: 560)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Copertina per «\(choice.track.displayName)»")
                .font(.headline)
                .lineLimit(2)
            Text("Discogs conosce \(releases.count) edizioni. Scegli quella che hai in mano: diventa la foto dell'etichetta del lato A, e il suo titolo riempie il campo Album.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
    }

    private var footer: some View {
        HStack {
            if isApplying {
                ProgressView().controlSize(.small)
                Text("Scarico la copertina…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Nessuna di queste") {
                model.dismissArtworkChoice(for: choice.track)
                dismiss()
            }
            .keyboardShortcut(.cancelAction)
            .disabled(isApplying)
        }
        .padding(16)
    }

    private func choose(_ release: DiscogsRelease) {
        isApplying = true
        Task {
            // Scelta a mano: da qui l'album si scrive anche sopra a quello che c'era, perché
            // indicare questa edizione fra dieci è già la conferma di quale disco sia.
            await model.applyArtwork(release, to: choice.track, chosenByHand: true)
            isApplying = false
            dismiss()
        }
    }
}

/// Una copertina nella griglia.
private struct ReleaseCell: View {
    let release: DiscogsRelease
    let onChoose: () -> Void

    var body: some View {
        Button(action: onChoose) {
            VStack(alignment: .leading, spacing: 6) {
                cover
                Text(release.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(release.details)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .help("Usa questa copertina")
    }

    /// `AsyncImage` e non un download nostro: sono miniature piccole, servono solo qui e non
    /// vanno tenute — scaricata è quella che si sceglie.
    @ViewBuilder
    private var cover: some View {
        ZStack(alignment: .topTrailing) {
            AsyncImage(url: release.thumbnailURL ?? release.coverURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure:
                    placeholder(symbol: "photo.badge.exclamationmark")
                default:
                    placeholder(symbol: "photo")
                }
            }
            .frame(width: 150, height: 150)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if release.isVinyl {
                Text("VINILE")
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(.tint, in: Capsule())
                    .foregroundStyle(.white)
                    .padding(5)
            }
        }
    }

    private func placeholder(symbol: String) -> some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Image(systemName: symbol).foregroundStyle(.tertiary)
        }
    }
}
