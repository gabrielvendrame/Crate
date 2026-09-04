import SwiftUI
import DJKit

/// La fascia dei deck, sempre visibile in fondo alla finestra.
///
/// I deck sono **impilati**, A sopra e B sotto: così ogni waveform occupa tutta la larghezza
/// disponibile e scorre in orizzontale, tempo da sinistra a destra. Affiancarli dimezzerebbe la
/// larghezza e renderebbe illeggibile proprio ciò che serve guardare.
/// Il motore audio arriva in M4: per ora sono due segnaposto con la geometria definitiva.
struct DeckBarView: View {
    var body: some View {
        VStack(spacing: 1) {
            DeckStrip(label: "A")
            DeckStrip(label: "B")
        }
        .background(.quaternary)
    }
}

private struct DeckStrip: View {
    let label: String

    var body: some View {
        HStack(spacing: 12) {
            // Colonna sinistra stretta: identità del deck e trasporto.
            VStack(alignment: .leading, spacing: 6) {
                Text("DECK \(label)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                HStack(spacing: 6) {
                    Image(systemName: "play.fill")
                    Text("CUE").font(.caption.weight(.bold))
                }
                .foregroundStyle(.tertiary)
            }
            .frame(width: 90, alignment: .leading)

            // Tutto il resto è waveform, a piena larghezza e in orizzontale.
            VStack(spacing: 4) {
                WaveformPlaceholder(height: 26, caption: nil)
                WaveformPlaceholder(height: 64, caption: "Nessuna traccia caricata")
            }
            .frame(maxWidth: .infinity)

            // Colonna destra stretta: fader del pitch.
            VStack(spacing: 4) {
                Text("PITCH")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Capsule()
                    .fill(.tertiary)
                    .frame(width: 4)
                Text("0.0%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .frame(width: 56)
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .underPageBackgroundColor))
    }
}

private struct WaveformPlaceholder: View {
    let height: CGFloat
    let caption: String?

    var body: some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color(nsColor: .textBackgroundColor).opacity(0.35))
            .frame(height: height)
            .overlay {
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
    }
}
