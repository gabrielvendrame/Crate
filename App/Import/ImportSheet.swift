import SwiftUI
import DJKit

/// Pannello di import: si incolla un link, si preme invio, il brano entra in coda.
///
/// Resta aperto dopo l'aggiunta perché i link si incollano quasi sempre a raffica.
struct ImportSheet: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    @Environment(\.dismiss) private var dismiss

    @State private var input = ""
    @FocusState private var isFieldFocused: Bool

    private var queue: ImportQueue? { model.importQueue }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            field
            if let queue, !queue.jobs.isEmpty {
                Divider()
                jobList(queue)
            }
            Divider()
            footer
        }
        .frame(width: 560)
        .frame(maxHeight: 520)
        .onAppear { isFieldFocused = true }
    }

    private var field: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aggiungi da YouTube")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("Incolla un link…", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .focused($isFieldFocused)
                    .onSubmit(add)

                Button("Incolla", systemImage: "doc.on.clipboard") {
                    if let string = NSPasteboard.general.string(forType: .string) {
                        input = string
                        add()
                    }
                }
                .labelStyle(.iconOnly)
                .help("Incolla dagli appunti e aggiungi")

                Button("Aggiungi", action: add)
                    .keyboardShortcut(.defaultAction)
                    .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Text("Il parametro di playlist nei link viene ignorato: viene importato solo il brano.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private func jobList(_ queue: ImportQueue) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(queue.jobs) { job in
                    ImportJobRow(job: job) { queue.remove(id: job.id) }
                    Divider()
                }
            }
        }
        .frame(minHeight: 80)
    }

    private var footer: some View {
        HStack {
            if let queue, queue.jobs.contains(where: { $0.state == .finished }) {
                Button("Pulisci completati") { queue.clearFinished() }
                    .buttonStyle(.link)
            }
            Spacer()
            Button("Chiudi") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(12)
    }

    private func add() {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        queue?.enqueue(text)
        input = ""
        isFieldFocused = true
    }
}

private struct ImportJobRow: View {
    let job: ImportJob
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                Text(job.displayTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let message = job.message {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(job.state == .failed ? .red : .secondary)
                        .lineLimit(2)
                } else if job.state == .downloading || job.state == .analyzing {
                    ProgressView(value: job.progress)
                        .progressViewStyle(.linear)
                } else if !job.state.isTerminal {
                    Text(stateText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if job.state.isTerminal {
                Button("Rimuovi", systemImage: "xmark", action: onRemove)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var stateText: String {
        switch job.state {
        case .queued: "In coda"
        case .fetchingInfo: "Leggo il video…"
        case .downloading: "Scarico…"
        case .converting: "Converto in ALAC…"
        case .importing: "Aggiungo alla libreria…"
        case .analyzing: "Calcolo la waveform…"
        case .finished: "Fatto"
        case .failed: "Errore"
        }
    }

    private var symbol: String {
        switch job.state {
        case .queued: "clock"
        case .fetchingInfo: "magnifyingglass"
        case .downloading: "arrow.down.circle"
        case .converting: "arrow.triangle.2.circlepath"
        case .importing: "tray.and.arrow.down"
        case .analyzing: "waveform"
        case .finished: "checkmark.circle.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch job.state {
        case .finished: .green
        case .failed: .red
        default: .accentColor
        }
    }
}
