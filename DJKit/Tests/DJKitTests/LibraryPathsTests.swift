import Foundation
import Testing
@testable import DJKit

@Suite("Percorsi della libreria")
struct LibraryPathsTests {

    @Test("Le cartelle vengono create tutte sotto la radice indicata")
    func createsAllDirectories() throws {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "CrateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LibraryPaths(root: root)
        try paths.createDirectories()

        for directory in paths.allDirectories {
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory)
            #expect(exists, "manca \(directory.lastPathComponent)")
            #expect(isDirectory.boolValue)
        }
    }

    @Test("I nomi dei file derivano dall'id della traccia")
    func filenameConventions() {
        let paths = LibraryPaths(root: URL(filePath: "/tmp/crate"))
        let id = "ABC-123"

        #expect(paths.audioFilename(trackID: id, fileExtension: "m4a") == "ABC-123.m4a")
        #expect(paths.peaksFilename(trackID: id) == "ABC-123.peaks")
        #expect(paths.artworkFilename(trackID: id, side: .a, fileExtension: "jpg") == "ABC-123-A.jpg")
        #expect(paths.artworkFilename(trackID: id, side: .b, fileExtension: "jpg") == "ABC-123-B.jpg")
    }

    @Test("La cartella di lavoro si svuota senza toccare il resto")
    func clearScratchLeavesLibraryAlone() throws {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "CrateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: root) }

        let paths = LibraryPaths(root: root)
        try paths.createDirectories()

        let leftover = paths.scratchDirectory.appending(path: "download.part")
        let keeper = paths.audioDirectory.appending(path: "traccia.m4a")
        try Data("x".utf8).write(to: leftover)
        try Data("x".utf8).write(to: keeper)

        try paths.clearScratch()

        #expect(!FileManager.default.fileExists(atPath: leftover.path))
        #expect(FileManager.default.fileExists(atPath: keeper.path))
    }
}
