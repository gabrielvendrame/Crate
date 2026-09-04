import Foundation
import Testing
@testable import DJKit

/// Prova la catena completa contro YouTube: interrogazione, download, spostamento in libreria,
/// riga sul database.
///
/// Escluso dalla suite normale — richiede rete, dura secondi e dipende da un video che potrebbe
/// sparire. Si lancia di proposito con:
///
///     CRATE_NETWORK_TESTS=1 swift test --package-path DJKit --filter ImportIntegration
@Suite("Import end-to-end (richiede rete)")
struct ImportIntegrationTests {

    private static var isEnabled: Bool {
        ProcessInfo.processInfo.environment["CRATE_NETWORK_TESTS"] != nil
    }

    /// I binari sidecar stanno nel repository, non nel bundle del test runner.
    private static var toolsDirectory: URL {
        URL(filePath: #filePath)                      // …/DJKit/Tests/DJKitTests/…
            .deletingLastPathComponent()              // DJKitTests
            .deletingLastPathComponent()              // Tests
            .deletingLastPathComponent()              // DJKit
            .deletingLastPathComponent()              // radice del progetto
            .appending(path: "Resources/Tools", directoryHint: .isDirectory)
    }

    @Test("Un link con playlist appresso importa un solo brano, pronto all'uso",
          .enabled(if: isEnabled),
          .timeLimit(.minutes(2)))
    @MainActor
    func importsSingleTrackFromPlaylistLink() async throws {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "CrateIntegration-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LibraryPaths(root: root)
        try paths.createDirectories()
        let database = try AppDatabase.open(at: paths.databaseURL)
        let repository = TrackRepository(database: database)
        let locator = ToolLocator(updatedDirectory: nil, bundledDirectory: Self.toolsDirectory)

        let queue = ImportQueue(
            runner: YtDlpRunner(locator: locator),
            converter: AudioConverter(locator: locator),
            repository: repository,
            paths: paths
        )

        queue.enqueue("https://www.youtube.com/watch?v=wqf-xIyf5y4&list=RDjLEvbgq2oEQ&index=7")

        while queue.jobs.first?.state.isTerminal != true {
            try await Task.sleep(for: .milliseconds(200))
        }

        let job = try #require(queue.jobs.first)
        #expect(job.state == .finished, "import fallito: \(job.message ?? "senza dettagli")")

        // Un solo brano, non l'intera radio del parametro `list=`.
        let tracks = try await repository.allTracks()
        #expect(tracks.count == 1)

        let track = try #require(tracks.first)
        #expect(track.youtubeID == "wqf-xIyf5y4")
        #expect(track.analysisState == .ready)
        #expect(track.artist == "FrescoEdits")
        #expect(track.title == "Jom")
        #expect(track.sampleRate == 44100)
        #expect(track.channelCount == 2)
        #expect(abs(track.durationSeconds - 345.4) < 1)

        // Il file è nella libreria, non nella cartella di lavoro, che resta pulita.
        let filename = try #require(track.audioFilename)
        let audioURL = paths.audioURL(filename: filename)
        #expect(FileManager.default.fileExists(atPath: audioURL.path))
        #expect(AudioConverter.isNativelyDecodable(audioURL))
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: paths.scratchDirectory.path)
        #expect(leftovers.isEmpty, "residui nella cartella di lavoro: \(leftovers)")
    }

    @Test("Lo stesso video non entra due volte", .enabled(if: isEnabled), .timeLimit(.minutes(2)))
    @MainActor
    func rejectsDuplicates() async throws {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "CrateIntegration-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LibraryPaths(root: root)
        try paths.createDirectories()
        let database = try AppDatabase.open(at: paths.databaseURL)
        let repository = TrackRepository(database: database)
        let locator = ToolLocator(updatedDirectory: nil, bundledDirectory: Self.toolsDirectory)
        let queue = ImportQueue(
            runner: YtDlpRunner(locator: locator),
            converter: AudioConverter(locator: locator),
            repository: repository,
            paths: paths
        )

        queue.enqueue("https://youtu.be/wqf-xIyf5y4")
        queue.enqueue("https://www.youtube.com/watch?v=wqf-xIyf5y4&list=RDjLEvbgq2oEQ")

        while queue.jobs.contains(where: { !$0.state.isTerminal }) {
            try await Task.sleep(for: .milliseconds(200))
        }

        #expect(queue.jobs.map(\.state) == [.finished, .failed])
        #expect(queue.jobs[1].message?.contains("Già in libreria") == true)
        #expect(try await repository.allTracks().count == 1)
    }
}
