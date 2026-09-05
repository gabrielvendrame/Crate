import DJKit
import SwiftUI

/// Il mixer: un gain per deck e il crossfader, nella striscia **fra i due deck**, che è dove sta
/// su un banco vero.
///
/// Niente EQ, per scelta di scope: qui si prepara un set da suonare su vinile, e l'equalizzazione
/// la farà il mixer del club. Quello che serve è sentire come legano due pezzi e a che volume
/// relativo.
struct MixerStrip: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }

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

            Divider().frame(height: 16)

            quantize
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    /// Il quantize sta qui, nella striscia in mezzo, perché **vale per entrambi i deck**: un
    /// interruttore per deck sarebbe due volte la stessa impostazione a due centimetri di
    /// distanza. Accanto, la risoluzione dell'aggancio.
    private var quantize: some View {
        @Bindable var model = model

        return HStack(spacing: 6) {
            Toggle(isOn: $model.isQuantizeEnabled) {
                Text("QUANTIZE")
                    .font(.caption2.weight(.semibold))
            }
            .toggleStyle(.button)
            .controlSize(.small)
            .help("I cue si agganciano alla battuta più vicina della griglia, invece di cadere dove capita")

            Picker("", selection: $model.quantizeResolution) {
                ForEach(QuantizeResolution.allCases, id: \.self) { resolution in
                    Text(resolution.label).tag(resolution)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 78)
            .disabled(!model.isQuantizeEnabled)
            .help("Quanto è fine l'aggancio: alla battuta o alla mezza battuta")
        }
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
