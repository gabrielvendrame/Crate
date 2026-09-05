import Foundation
import Observation

public enum ImportJobState: Sendable, Equatable {
    case queued
    case fetchingInfo
    case downloading
    case converting
    case importing
    case analyzing
    case finished
    case failed

    public var isTerminal: Bool { self == .finished || self == .failed }
}

public struct ImportJob: Identifiable, Sendable, Equatable {
    public let id: String
    public let input: String
    public var videoID: String?
    public var displayTitle: String
    public var state: ImportJobState
    public var progress: Double
    public var message: String?

    init(input: String) {
        self.id = UUID().uuidString
        self.input = input
        self.displayTitle = input
        self.state = .queued
        self.progress = 0
    }
}

public enum ImportError: LocalizedError {
    case notAYouTubeLink
    case alreadyInLibrary(title: String)

    public var errorDescription: String? {
        switch self {
        case .notAYouTubeLink:
            "Non sembra un link di YouTube."
        case .alreadyInLibrary(let title):
            "Già in libreria: \(title)"
        }
    }
}

/// Coda di import, seriale.
///
/// Seriale di proposito: due download in parallelo si contendono la banda senza finire prima, e
/// l'analisi che segue è comunque legata alla CPU. Un lavoro fallito non blocca la coda — viene
/// marcato e si passa al successivo.
@MainActor
@Observable
public final class ImportQueue {
    public private(set) var jobs: [ImportJob] = []

    /// Chiamato quando un brano è entrato in libreria ed è stato analizzato.
    ///
    /// La coda si ferma a YouTube: cosa succede dopo — cercare la copertina su Discogs, per
    /// esempio — non la riguarda, e infilarcelo dentro legherebbe l'import a un servizio che
    /// può non essere configurato.
    public var onTrackImported: ((Track) -> Void)?

    private let runner: YtDlpRunner
    private let converter: AudioConverter
    private let repository: TrackRepository
    private let paths: LibraryPaths
    private let analyzer: TrackAnalyzer
    private var isDraining = false

    public init(
        runner: YtDlpRunner,
        converter: AudioConverter,
        repository: TrackRepository,
        paths: LibraryPaths
    ) {
        self.runner = runner
        self.converter = converter
        self.repository = repository
        self.paths = paths
        self.analyzer = TrackAnalyzer(paths: paths, repository: repository)
    }

    public var activeCount: Int {
        jobs.filter { !$0.state.isTerminal }.count
    }

    public func enqueue(_ input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        jobs.append(ImportJob(input: trimmed))
        drainIfNeeded()
    }

    public func clearFinished() {
        jobs.removeAll { $0.state == .finished }
    }

    public func remove(id: String) {
        jobs.removeAll { $0.id == id && $0.state.isTerminal }
    }

    private func drainIfNeeded() {
        guard !isDraining else { return }
        isDraining = true
        Task {
            while let next = jobs.first(where: { $0.state == .queued }) {
                await process(jobID: next.id)
            }
            isDraining = false
        }
    }

    // MARK: - Esecuzione di un lavoro

    private func process(jobID: String) async {
        var trackID: String?
        do {
            update(jobID) { $0.state = .fetchingInfo }
            let input = job(jobID)?.input ?? ""

            guard let videoID = YouTubeURL.videoID(from: input) else {
                throw ImportError.notAYouTubeLink
            }
            update(jobID) { $0.videoID = videoID }

            if let existing = try await repository.track(youtubeID: videoID) {
                throw ImportError.alreadyInLibrary(title: existing.displayName)
            }

            let info = try await runner.fetchInfo(url: YouTubeURL.canonicalURL(videoID: videoID))
            let parsed = MetadataParser.parse(videoTitle: info.title, uploader: info.uploader)

            var track = Track(
                youtubeID: info.id,
                youtubeURL: info.webpageURL,
                title: parsed.title,
                artist: parsed.artist,
                durationSeconds: info.durationSeconds,
                analysisState: .downloading
            )
            trackID = track.id
            try await repository.save(track)
            update(jobID) {
                $0.displayTitle = track.displayName
                $0.state = .downloading
            }

            // Scarico in una cartella di lavoro: la libreria non deve mai vedere file parziali.
            let workingDirectory = paths.scratchDirectory.appending(
                path: track.id, directoryHint: .isDirectory
            )
            try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: workingDirectory) }

            var downloaded = try await runner.downloadAudio(
                url: YouTubeURL.canonicalURL(videoID: videoID),
                into: workingDirectory,
                onProgress: { [weak self] fraction in
                    Task { @MainActor in
                        self?.update(jobID) { $0.progress = fraction }
                    }
                }
            )

            // Opus in WebM: AVFoundation non lo apre, va portato in ALAC.
            if !AudioConverter.isNativelyDecodable(downloaded) {
                update(jobID) { $0.state = .converting }
                let converted = workingDirectory.appending(path: "\(track.id).m4a")
                downloaded = try await converter.convertToALAC(source: downloaded, destination: converted)
            }

            update(jobID) { $0.state = .importing }
            try await repository.updateAnalysisState(trackID: track.id, to: .analyzing)

            let fileInfo = try await probe(downloaded)
            let filename = paths.audioFilename(
                trackID: track.id,
                fileExtension: downloaded.pathExtension.isEmpty ? "m4a" : downloaded.pathExtension
            )
            let finalURL = paths.audioURL(filename: filename)
            try? FileManager.default.removeItem(at: finalURL)
            try FileManager.default.moveItem(at: downloaded, to: finalURL)

            track.audioFilename = filename
            track.durationSeconds = fileInfo.durationSeconds
            track.sampleRate = fileInfo.sampleRate
            track.channelCount = fileInfo.channelCount
            track.analysisState = .analyzing
            try await repository.save(track)

            // Analisi: è l'ultimo passo perché è l'unico che si può rifare da solo in seguito, e
            // una traccia senza waveform resta comunque in libreria. Da M6 la stessa passata
            // calcola anche BPM e beatgrid.
            update(jobID) {
                $0.state = .analyzing
                $0.progress = 0
            }
            try await analyzer.analyze(track: track) { [weak self] fraction in
                Task { @MainActor in
                    self?.update(jobID) { $0.progress = fraction }
                }
            }

            update(jobID) {
                $0.displayTitle = track.displayName
                $0.progress = 1
                $0.state = .finished
                $0.message = nil
            }
            onTrackImported?(track)
        } catch {
            let description = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            if let trackID {
                try? await repository.updateAnalysisState(trackID: trackID, to: .failed, error: description)
            }
            update(jobID) {
                $0.state = .failed
                $0.message = description
            }
        }
    }

    /// Apertura e lettura dell'intestazione fuori dal main actor: è I/O su disco.
    private nonisolated func probe(_ url: URL) async throws -> AudioFileInfo {
        try await Task.detached(priority: .userInitiated) {
            try AudioFileInfo.read(from: url)
        }.value
    }

    private func job(_ id: String) -> ImportJob? {
        jobs.first { $0.id == id }
    }

    private func update(_ id: String, _ transform: (inout ImportJob) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        transform(&jobs[index])
    }
}
