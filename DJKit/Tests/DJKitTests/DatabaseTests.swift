import Foundation
import Testing
@testable import DJKit

@Suite("Schema e persistenza")
struct DatabaseTests {

    private func makeTrack(youtubeID: String = "dQw4w9WgXcQ") -> Track {
        Track(
            youtubeID: youtubeID,
            youtubeURL: "https://www.youtube.com/watch?v=\(youtubeID)",
            title: "Test",
            artist: "Artista"
        )
    }

    @Test("Le migrazioni girano su un database vuoto e la traccia fa round-trip")
    func migrateAndRoundTrip() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TrackRepository(database: database)

        let track = makeTrack()
        try await repository.save(track)

        let fetched = try #require(try await repository.track(id: track.id))
        #expect(fetched.youtubeID == track.youtubeID)
        #expect(fetched.title == "Test")
        #expect(fetched.analysisState == .pending)
        #expect(fetched.bpm == nil)
    }

    @Test("youtubeID è unico: lo stesso video non entra due volte")
    func youtubeIDIsUnique() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TrackRepository(database: database)

        try await repository.save(makeTrack())
        await #expect(throws: (any Error).self) {
            try await repository.save(makeTrack())
        }
    }

    @Test("Eliminando la traccia spariscono anche i suoi cue point")
    func deletingTrackCascadesToCuePoints() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TrackRepository(database: database)

        let track = makeTrack()
        try await repository.save(track)
        try await repository.save(CuePoint(trackID: track.id, positionSeconds: 12, label: "drop"))
        #expect(try await repository.cuePoints(trackID: track.id).count == 1)

        try await repository.deleteTrack(id: track.id)
        #expect(try await repository.cuePoints(trackID: track.id).isEmpty)
    }

    @Test("I memory cue sono illimitati, gli hot cue occupano uno slot solo")
    func hotCueSlotsAreExclusiveButMemoryCuesAreNot() async throws {
        let database = try AppDatabase.inMemory()
        let repository = TrackRepository(database: database)
        let track = makeTrack()
        try await repository.save(track)

        // Tre memory cue: nessun conflitto, hotcueSlot resta NULL.
        for second in [10.0, 20.0, 30.0] {
            try await repository.save(CuePoint(trackID: track.id, positionSeconds: second))
        }
        #expect(try await repository.cuePoints(trackID: track.id).count == 3)

        // Assegnare lo slot 1 a un secondo cue libera il primo, non fallisce.
        let first = CuePoint(trackID: track.id, positionSeconds: 40)
        let second = CuePoint(trackID: track.id, positionSeconds: 50)
        try await repository.assignHotCue(first, toSlot: 1)
        try await repository.assignHotCue(second, toSlot: 1)

        let cues = try await repository.cuePoints(trackID: track.id)
        let withSlot1 = cues.filter { $0.hotcueSlot == 1 }
        #expect(withSlot1.count == 1)
        #expect(withSlot1.first?.id == second.id)
    }

    @Test("Cancellare una traccia lascia in scaletta un segnaposto, non un buco")
    func deletingTrackLeavesPlaceholderInPlaylist() async throws {
        let database = try AppDatabase.inMemory()
        let tracks = TrackRepository(database: database)
        let playlists = PlaylistRepository(database: database)

        let track = makeTrack()
        try await tracks.save(track)
        let playlist = try await playlists.createPlaylist(name: "Sabato")
        try await playlists.appendTrack(track.id, to: playlist.id)

        try await tracks.deleteTrack(id: track.id)

        let entries = try await playlists.entries(playlistID: playlist.id)
        #expect(entries.count == 1)
        #expect(entries[0].item.kind == .track)
        #expect(entries[0].item.trackID == nil)
        #expect(entries[0].track == nil)
    }
}
