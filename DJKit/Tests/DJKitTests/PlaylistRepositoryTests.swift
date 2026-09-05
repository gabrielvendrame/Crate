import Foundation
import Testing
@testable import DJKit

@Suite("Ordinamento delle scalette")
struct PlaylistRepositoryTests {

    private func makeFixture() async throws -> (PlaylistRepository, Playlist, [Track]) {
        let database = try AppDatabase.inMemory()
        let trackRepository = TrackRepository(database: database)
        let playlistRepository = PlaylistRepository(database: database)

        let tracks = try await (0..<4).asyncMap { index -> Track in
            let track = Track(
                youtubeID: "video\(index)",
                youtubeURL: "https://youtu.be/video\(index)",
                title: "Traccia \(index)"
            )
            try await trackRepository.save(track)
            return track
        }
        let playlist = try await playlistRepository.createPlaylist(name: "Set")
        return (playlistRepository, playlist, tracks)
    }

    @Test("Le tracce accodate mantengono l'ordine di inserimento")
    func appendKeepsOrder() async throws {
        let (repository, playlist, tracks) = try await makeFixture()
        for track in tracks {
            try await repository.appendTrack(track.id, to: playlist.id)
        }

        let entries = try await repository.entries(playlistID: playlist.id)
        #expect(entries.map(\.item.position) == [0, 1, 2, 3])
        #expect(entries.map(\.track?.title) == ["Traccia 0", "Traccia 1", "Traccia 2", "Traccia 3"])
    }

    /// È il caso del drop in mezzo alla scaletta, che è il gesto principale dell'editor.
    @Test("Un brano lasciato cadere su una riga si incunea prima di quella")
    func trackInsertsBeforeRow() async throws {
        let (repository, playlist, tracks) = try await makeFixture()
        for track in tracks.prefix(3) {
            try await repository.appendTrack(track.id, to: playlist.id)
        }

        try await repository.insertTrack(tracks[3].id, into: playlist.id, at: 1)

        let entries = try await repository.entries(playlistID: playlist.id)
        #expect(entries.map(\.item.position) == [0, 1, 2, 3])
        #expect(
            entries.map(\.track?.title)
                == ["Traccia 0", "Traccia 3", "Traccia 1", "Traccia 2"]
        )
    }

    /// Trascinando più brani insieme, l'editor li inserisce uno dopo l'altro a indici crescenti:
    /// se l'ordine si rovesciasse, una selezione multipla arriverebbe in scaletta al contrario.
    @Test("Più brani inseriti di fila allo stesso punto restano nell'ordine in cui sono partiti")
    func multipleInsertsKeepDropOrder() async throws {
        let (repository, playlist, tracks) = try await makeFixture()
        try await repository.appendTrack(tracks[0].id, to: playlist.id)
        try await repository.appendTrack(tracks[1].id, to: playlist.id)

        for (offset, track) in tracks[2...3].enumerated() {
            try await repository.insertTrack(track.id, into: playlist.id, at: 1 + offset)
        }

        let entries = try await repository.entries(playlistID: playlist.id)
        #expect(entries.map(\.item.position) == [0, 1, 2, 3])
        #expect(
            entries.map(\.track?.title)
                == ["Traccia 0", "Traccia 2", "Traccia 3", "Traccia 1"]
        )
    }

    @Test("Una nota si incunea fra due brani facendo scorrere i successivi")
    func noteInsertsBetweenTracks() async throws {
        let (repository, playlist, tracks) = try await makeFixture()
        for track in tracks.prefix(2) {
            try await repository.appendTrack(track.id, to: playlist.id)
        }

        try await repository.insertNote("Alzare i bassi qui", into: playlist.id, at: 1)

        let entries = try await repository.entries(playlistID: playlist.id)
        #expect(entries.map(\.item.kind) == [.track, .note, .track])
        #expect(entries.map(\.item.position) == [0, 1, 2])
        #expect(entries[1].item.text == "Alzare i bassi qui")
    }

    @Test("Una nota può stare in testa alla scaletta")
    func noteCanBeFirst() async throws {
        let (repository, playlist, tracks) = try await makeFixture()
        try await repository.appendTrack(tracks[0].id, to: playlist.id)
        try await repository.insertNote("Apertura", into: playlist.id, at: 0)

        let entries = try await repository.entries(playlistID: playlist.id)
        #expect(entries.map(\.item.kind) == [.note, .track])
    }

    @Test("Il riordino da drag & drop riscrive posizioni dense")
    func reorderProducesDensePositions() async throws {
        let (repository, playlist, tracks) = try await makeFixture()
        for track in tracks {
            try await repository.appendTrack(track.id, to: playlist.id)
        }
        try await repository.insertNote("Transizione", into: playlist.id, at: 2)

        var entries = try await repository.entries(playlistID: playlist.id)
        // Sposta l'ultima riga in testa, come farebbe un drop.
        let reordered = [entries.last!.id] + entries.dropLast().map(\.id)
        try await repository.reorder(playlistID: playlist.id, orderedItemIDs: reordered)

        entries = try await repository.entries(playlistID: playlist.id)
        #expect(entries.map(\.item.position) == [0, 1, 2, 3, 4])
        #expect(entries.map(\.id) == reordered)
    }

    @Test("Eliminando una riga le posizioni si ricompattano")
    func deleteCompactsPositions() async throws {
        let (repository, playlist, tracks) = try await makeFixture()
        for track in tracks {
            try await repository.appendTrack(track.id, to: playlist.id)
        }

        let entries = try await repository.entries(playlistID: playlist.id)
        try await repository.deleteItem(id: entries[1].id, in: playlist.id)

        let remaining = try await repository.entries(playlistID: playlist.id)
        #expect(remaining.map(\.item.position) == [0, 1, 2])
        #expect(remaining.map(\.track?.title) == ["Traccia 0", "Traccia 2", "Traccia 3"])
    }

    @Test("Eliminare la scaletta porta via anche le sue righe")
    func deletingPlaylistCascades() async throws {
        let (repository, playlist, tracks) = try await makeFixture()
        try await repository.appendTrack(tracks[0].id, to: playlist.id)

        try await repository.deletePlaylist(id: playlist.id)

        #expect(try await repository.entries(playlistID: playlist.id).isEmpty)
        #expect(try await repository.allPlaylists().isEmpty)
    }
}

private extension Sequence {
    /// `map` con una trasformazione asincrona, in sequenza.
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var result: [T] = []
        for element in self {
            result.append(try await transform(element))
        }
        return result
    }
}
