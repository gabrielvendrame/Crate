import Foundation
import Testing
@testable import DJKit

@Suite("Tag")
struct TagRepositoryTests {

    private func makeTrack(_ id: String) -> Track {
        Track(
            youtubeID: id,
            youtubeURL: "https://www.youtube.com/watch?v=\(id)",
            title: "Brano \(id)"
        )
    }

    private func makeRepositories() throws -> (TagRepository, TrackRepository) {
        let database = try AppDatabase.inMemory()
        return (TagRepository(database: database), TrackRepository(database: database))
    }

    @Test("Un tag creato si ritrova, con nome ripulito e posizione in coda")
    func createAndFetch() async throws {
        let (tags, _) = try makeRepositories()

        let disco = try await tags.createTag(name: "  disco ")
        let funky = try await tags.createTag(name: "funky")

        #expect(disco.name == "disco")
        #expect(disco.position == 0)
        #expect(funky.position == 1)
        #expect(try await tags.allTags().map(\.name) == ["disco", "funky"])
    }

    @Test("Creare un tag che esiste già restituisce quello, anche scritto con altre maiuscole")
    func createIsIdempotent() async throws {
        let (tags, _) = try makeRepositories()

        let first = try await tags.createTag(name: "disco")
        let again = try await tags.createTag(name: "Disco")

        #expect(first.id == again.id)
        #expect(try await tags.allTags().count == 1)
    }

    @Test("Un nome vuoto non fa un tag")
    func emptyNameIsRejected() async throws {
        let (tags, _) = try makeRepositories()
        await #expect(throws: TagError.emptyName) {
            _ = try await tags.createTag(name: "   ")
        }
    }

    @Test("Rinominare su un nome già preso fallisce, invece di fondere due tag")
    func renameClashIsRejected() async throws {
        let (tags, _) = try makeRepositories()
        _ = try await tags.createTag(name: "disco")
        var funky = try await tags.createTag(name: "funky")

        funky.name = "Disco"
        await #expect(throws: TagError.duplicateName("disco")) {
            try await tags.save(funky)
        }
        #expect(try await tags.allTags().count == 2)
    }

    @Test("I tag si assegnano a più tracce insieme, e assegnarli due volte non raddoppia niente")
    func assignToManyTracks() async throws {
        let (tags, tracks) = try makeRepositories()
        let a = makeTrack("aaa"), b = makeTrack("bbb")
        try await tracks.save(a)
        try await tracks.save(b)
        let disco = try await tags.createTag(name: "disco")

        try await tags.addTag(id: disco.id, toTracks: [a.id, b.id])
        try await tags.addTag(id: disco.id, toTracks: [a.id])

        let map = try await tags.tagIDsByTrack()
        #expect(map[a.id] == [disco.id])
        #expect(map[b.id] == [disco.id])
    }

    @Test("Togliere un tag lo toglie solo alle tracce indicate")
    func removeFromSomeTracks() async throws {
        let (tags, tracks) = try makeRepositories()
        let a = makeTrack("aaa"), b = makeTrack("bbb")
        try await tracks.save(a)
        try await tracks.save(b)
        let disco = try await tags.createTag(name: "disco")
        try await tags.addTag(id: disco.id, toTracks: [a.id, b.id])

        try await tags.removeTag(id: disco.id, fromTracks: [a.id])

        let map = try await tags.tagIDsByTrack()
        #expect(map[a.id] == nil)
        #expect(map[b.id] == [disco.id])
    }

    @Test("I tag di una traccia si riscrivono in blocco")
    func setTagsReplaces() async throws {
        let (tags, tracks) = try makeRepositories()
        let track = makeTrack("aaa")
        try await tracks.save(track)
        let disco = try await tags.createTag(name: "disco")
        let funky = try await tags.createTag(name: "funky")
        try await tags.addTag(id: disco.id, toTracks: [track.id])

        try await tags.setTags(ids: [funky.id], forTrack: track.id)

        #expect(try await tags.tagIDsByTrack()[track.id] == [funky.id])
    }

    @Test("Cancellare un tag toglie anche i legami, e cancellare una traccia pure")
    func cascades() async throws {
        let (tags, tracks) = try makeRepositories()
        let track = makeTrack("aaa")
        try await tracks.save(track)
        let disco = try await tags.createTag(name: "disco")
        let funky = try await tags.createTag(name: "funky")
        try await tags.addTag(id: disco.id, toTracks: [track.id])
        try await tags.addTag(id: funky.id, toTracks: [track.id])

        try await tags.deleteTag(id: disco.id)
        #expect(try await tags.tagIDsByTrack()[track.id] == [funky.id])

        try await tracks.deleteTrack(id: track.id)
        #expect(try await tags.tagIDsByTrack().isEmpty)
    }

    @Test("Il riordino riscrive le posizioni in modo denso")
    func reorder() async throws {
        let (tags, _) = try makeRepositories()
        let disco = try await tags.createTag(name: "disco")
        let funky = try await tags.createTag(name: "funky")
        let house = try await tags.createTag(name: "house")

        try await tags.reorderTags(idsInOrder: [house.id, disco.id, funky.id])

        let ordered = try await tags.allTags()
        #expect(ordered.map(\.name) == ["house", "disco", "funky"])
        #expect(ordered.map(\.position) == [0, 1, 2])
    }
}
