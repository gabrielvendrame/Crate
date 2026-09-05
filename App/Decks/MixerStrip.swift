import SwiftUI

/// Il mixer: un gain per deck e il crossfader, nella striscia **fra i due deck**, che è dove sta
/// su un banco vero.
///
/// Niente EQ, per scelta di scope: qui si prepara un set da suonare su vinile, e l'equalizzazione
/// la farà il mixer del club. Quello che serve è sentire come legano due pezzi e a che volume
/// relativo.
struct MixerStrip: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model

        return HStack(spacing: 14) {
            gain(for: model.deckA, label: "GAIN A")

            Spacer(minLength: 8)

            HStack(spacing: 6) {
                Text("A")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                HorizontalFader(value: $model.crossfader, resetValue: 0.5)
                    .frame(width: 260)
                    .help("Crossfader: al centro suonano entrambi i deck · doppio clic per centrarlo")
                Text("B")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            gain(for: model.deckB, label: "GAIN B")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func gain(for deck: DeckState, label: String) -> some View {
        @Bindable var deck = deck

        return HStack(spacing: 5) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            HorizontalFader(value: $deck.gain, resetValue: 1)
                .frame(width: 84)
                .help("Volume del deck · doppio clic per riportarlo al massimo")
        }
    }
}
