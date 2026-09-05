import DJKit
import SwiftUI

/// Le due sole impostazioni che questa app ha: il token di Discogs e l'aggiornamento di yt-dlp.
///
/// Sono qui insieme perché sono la stessa cosa da un certo punto di vista — i due punti in cui
/// l'app dipende da qualcosa che sta fuori — e perché due fogli separati per due campi sarebbero
/// due voci di menu in più da ricordare.
struct SettingsSheet: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    @Environment(\.dismiss) private var dismiss

    @State private var token = ""
    @State private var didSaveToken = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Impostazioni")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button("Chiudi") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    discogs
                    Divider()
                    ytDlp
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 520)
        .task {
            token = model.discogsToken?.read() ?? ""
            model.refreshInstalledYtDlpVersion()
        }
    }

    // MARK: - Discogs

    private var discogs: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Copertine da Discogs")
                .font(.headline)

            Text("Appena un brano arriva da YouTube, l'app cerca l'edizione su Discogs e ne prende la copertina. Se ne trova più d'una te le mostra e scegli tu; se ne trova una sola la usa.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                // Non è un `SecureField`: un token va **riletto e confrontato** con quello sul
                // sito quando qualcosa non funziona, e nasconderlo lo renderebbe solo più
                // difficile da correggere. Non è una password, dà accesso in lettura a un
                // catalogo pubblico e si revoca in un clic.
                TextField("Token personale", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .font(.callout.monospaced())
                    .onSubmit(saveToken)

                Button("Salva", action: saveToken)
                    .disabled(token == (model.discogsToken?.read() ?? ""))
            }

            HStack(spacing: 6) {
                if didSaveToken {
                    Label("Salvato", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else if model.hasDiscogsToken {
                    Label("Token presente", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Nessun token: la ricerca è spenta", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Link(
                    "Dove si genera",
                    destination: URL(string: "https://www.discogs.com/settings/developers")!
                )
                .font(.caption)
            }

            Text("Il token finisce in un file leggibile solo da te, dentro la cartella della libreria. Non è il portachiavi: l'app è firmata ad hoc e la firma cambia a ogni compilazione, quindi il portachiavi chiederebbe l'autorizzazione ogni volta.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func saveToken() {
        model.saveDiscogsToken(token)
        didSaveToken = true
    }

    // MARK: - yt-dlp

    private var ytDlp: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Aggiorna yt-dlp")
                .font(.headline)

            Text("È lo strumento che scarica l'audio da YouTube. Invecchia in fretta: quando YouTube cambia qualcosa smette di funzionare, e l'errore che compare non dice che è colpa della versione.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            LabeledContent("Versione in uso") {
                Text(model.installedYtDlpVersion ?? "sconosciuta")
                    .monospacedDigit()
            }

            updateStatus

            HStack {
                Spacer()
                Button("Scarica l'ultima versione") { model.updateYtDlp() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isUpdating)
            }
        }
    }

    private var isUpdating: Bool {
        if case .running = model.toolsUpdateState { return true }
        return false
    }

    @ViewBuilder
    private var updateStatus: some View {
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
