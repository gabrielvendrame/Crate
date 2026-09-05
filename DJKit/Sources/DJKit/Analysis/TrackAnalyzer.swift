import Foundation

public enum TrackAnalysisError: LocalizedError {
    case missingAudio

    public var errorDescription: String? {
        switch self {
        case .missingAudio:
            "Nessun file audio da analizzare: la traccia va riscaricata."
        }
    }
}

/// Passa una traccia scaricata attraverso decodifica, calcolo dei peaks e rilevamento del tempo,
/// scrive la cache su disco e aggiorna la riga nel database.
///
/// Il lavoro pesante gira su un task staccato: la decodifica alloca centinaia di MB e le due STFT
/// occupano un core per qualche secondo, nessuna delle due cose può stare sul main actor.
///
/// **Peaks e tempo si calcolano nella stessa passata** perché condividono il pezzo caro: la
/// traccia decodificata. Farne due comandi separati vorrebbe dire decodificare due volte lo stesso
/// file per centinaia di MB, e nella pratica non c'è motivo di volere l'uno senza l'altro.
public struct TrackAnalyzer: Sendable {
    private let paths: LibraryPaths
    private let repository: TrackRepository

    public init(paths: LibraryPaths, repository: TrackRepository) {
        self.paths = paths
        self.repository = repository
    }

    /// Ricalcola i peaks di una traccia. Restituisce la riga aggiornata.
    @discardableResult
    public func analyze(
        track: Track,
        onProgress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> Track {
        guard let audioFilename = track.audioFilename else {
            try? await repository.updateAnalysisState(
                trackID: track.id,
                to: .failed,
                error: TrackAnalysisError.missingAudio.errorDescription
            )
            throw TrackAnalysisError.missingAudio
        }

        let audioURL = paths.audioURL(filename: audioFilename)
        let peaksFilename = paths.peaksFilename(trackID: track.id)
        let peaksURL = paths.peaksURL(filename: peaksFilename)

        try await repository.updateAnalysisState(trackID: track.id, to: .analyzing)

        let tempo: TempoEstimate?
        do {
            tempo = try await Task.detached(priority: .utility) {
                // La decodifica è I/O più decodifica AAC: circa un quarto del tempo totale.
                let audio = try AudioDecoder.decode(url: audioURL) { onProgress?($0 * 0.25) }
                let peaks = PeaksBuilder.build(audio) { onProgress?(0.25 + $0 * 0.45) }
                try PeaksFile.write(peaks, to: peaksURL)
                // Il tempo per ultimo: se il rilevamento non conclude nulla, la waveform è
                // comunque già su disco e la traccia resta usabile.
                return TempoAnalyzer.analyze(audio) { onProgress?(0.7 + $0 * 0.3) }
            }.value
        } catch {
            let description = (error as? LocalizedError)?.errorDescription
                ?? error.localizedDescription
            try? await repository.updateAnalysisState(
                trackID: track.id, to: .failed, error: description
            )
            throw error
        }

        // Si riscrivono solo le colonne dell'analisi: nel frattempo l'utente può aver corretto i
        // metadati dall'ispettore, e riscrivere la traccia intera glieli cancellerebbe.
        try await repository.updateAnalysis(
            trackID: track.id,
            peaksFilename: peaksFilename,
            tempo: tempo
        )
        return try await repository.track(id: track.id) ?? track
    }

    /// Carica la cache di una traccia, fuori dal main actor. `nil` se non è ancora stata calcolata.
    public func loadPeaks(for track: Track) async throws -> Peaks? {
        guard let filename = track.peaksFilename else { return nil }
        let url = paths.peaksURL(filename: filename)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try await Task.detached(priority: .userInitiated) {
            try PeaksFile.read(from: url)
        }.value
    }
}
