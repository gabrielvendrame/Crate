import AVFoundation
import Foundation
import Testing
@testable import DJKit

@Suite("Analisi di una traccia")
struct TrackAnalyzerTests {

    /// Radice di libreria usa e getta: i test non devono mai avvicinarsi a quella vera.
    private func makeLibrary() throws -> LibraryPaths {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "CrateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let paths = LibraryPaths(root: root)
        try paths.createDirectories()
        return paths
    }

    /// Scrive un vero file audio su disco: il percorso da verificare è quello completo, dal file
    /// alla riga del database, non il solo calcolo in memoria.
    private func writeSine(to url: URL, seconds: Double = 2, frequency: Double = 1_000) throws {
        let sampleRate = 44_100.0
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )!
        let frameCount = AVAudioFrameCount(sampleRate * seconds)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        for channel in 0..<2 {
            let samples = buffer.floatChannelData![channel]
            for frame in 0..<Int(frameCount) {
                samples[frame] = Float(sin(2 * .pi * frequency * Double(frame) / sampleRate))
            }
        }

        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    @Test("Dal file audio nascono i peaks su disco e la riga passa a pronta")
    func analyzeWritesPeaksAndUpdatesTrack() async throws {
        let paths = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: paths.root) }

        let database = try AppDatabase.inMemory()
        let repository = TrackRepository(database: database)

        var track = Track(youtubeID: "abc12345678", youtubeURL: "https://example.invalid")
        let audioFilename = paths.audioFilename(trackID: track.id, fileExtension: "wav")
        try writeSine(to: paths.audioURL(filename: audioFilename))
        track.audioFilename = audioFilename
        track.analysisState = .analyzing
        try await repository.save(track)

        let analyzer = TrackAnalyzer(paths: paths, repository: repository)
        let analyzed = try await analyzer.analyze(track: track)

        #expect(analyzed.analysisState == .ready)
        #expect(analyzed.analysisError == nil)
        let peaksFilename = try #require(analyzed.peaksFilename)
        #expect(FileManager.default.fileExists(atPath: paths.peaksURL(filename: peaksFilename).path))

        let peaks = try #require(try await analyzer.loadPeaks(for: analyzed))
        #expect(peaks.channelCount == 2)
        #expect(abs(peaks.durationSeconds - 2) < 0.05)
        #expect(peaks.levels.map(\.binSize) == PeaksBuilder.binSizes)
    }

    @Test("L'analisi non calpesta i metadati corretti nel frattempo")
    func analyzeKeepsConcurrentEdits() async throws {
        let paths = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: paths.root) }

        let database = try AppDatabase.inMemory()
        let repository = TrackRepository(database: database)

        var track = Track(youtubeID: "def12345678", youtubeURL: "https://example.invalid")
        let audioFilename = paths.audioFilename(trackID: track.id, fileExtension: "wav")
        try writeSine(to: paths.audioURL(filename: audioFilename))
        track.audioFilename = audioFilename
        try await repository.save(track)

        // Come se l'ispettore avesse salvato mentre l'analisi girava.
        var edited = track
        edited.title = "Titolo corretto a mano"
        edited.artist = "Artista corretto a mano"
        try await repository.save(edited)

        let analyzer = TrackAnalyzer(paths: paths, repository: repository)
        let analyzed = try await analyzer.analyze(track: track)

        #expect(analyzed.title == "Titolo corretto a mano")
        #expect(analyzed.artist == "Artista corretto a mano")
        #expect(analyzed.peaksFilename != nil)
    }

    @Test("Senza file audio l'analisi fallisce e lo scrive sulla riga")
    func analyzeWithoutAudioFails() async throws {
        let paths = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: paths.root) }

        let database = try AppDatabase.inMemory()
        let repository = TrackRepository(database: database)

        let track = Track(youtubeID: "ghi12345678", youtubeURL: "https://example.invalid")
        try await repository.save(track)

        let analyzer = TrackAnalyzer(paths: paths, repository: repository)
        await #expect(throws: TrackAnalysisError.self) {
            try await analyzer.analyze(track: track)
        }

        let stored = try #require(try await repository.track(id: track.id))
        #expect(stored.analysisState == .failed)
        #expect(stored.analysisError != nil)
        #expect(stored.peaksFilename == nil)
    }
}
