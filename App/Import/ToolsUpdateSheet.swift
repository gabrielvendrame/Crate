import DJKit
import SwiftUI

/// Aggiornamento di yt-dlp, in un foglio suo.
///
/// Ha un foglio e non una sola voce di menu perché è l'unico posto dove si può dire **perché**
/// esiste: quando YouTube cambia, la copia impacchettata smette di scaricare e l'errore che
/// compare non nomina la versione. Qui si vede quale versione è in uso e si aggiorna, e il
/// download è di 124 MB — un minuto in cui va mostrato a che punto è.
struct ToolsUpdateSheet: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Aggiorna yt-dlp")
                    .font(.title3.weight(.semibold))
                Text("È lo strumento che scarica l'audio da YouTube. Invecchia in fretta: quando YouTube cambia qualcosa, smette di funzionare e l'errore non dice che è colpa della versione.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LabeledContent("Versione in uso") {
                Text(model.installedYtDlpVersion ?? "sconosciuta")
                    .monospacedDigit()
            }

            status

            Spacer(minLength: 0)

            HStack {
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Scarica l'ultima versione") { model.updateYtDlp() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isRunning)
            }
        }
        .padding(20)
        .frame(width: 440, height: 300)
        .task { model.refreshInstalledYtDlpVersion() }
    }

    private var isRunning: Bool {
        if case .running = model.toolsUpdateState { return true }
        return false
    }

    @ViewBuilder
    private var status: some View {
        switch model.toolsUpdateState {
        case .idle:
            Text("Il pacchetto pesa circa 124 MB: è la variante a cartella, la sola che si avvii in mezzo secondo invece che in tredici.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)

        case .running(let fraction):
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: fraction)
                Text(fraction < 0.1 ? "Cerco l'ultima release…" : "Scarico… \(Int(fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

        case .succeeded(let version):
            Label("Installata la versione \(version).", systemImage: "checkmark.circle")
                .font(.callout)
                .foregroundStyle(.green)

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.callout)
                .foregroundStyle(.orange)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
