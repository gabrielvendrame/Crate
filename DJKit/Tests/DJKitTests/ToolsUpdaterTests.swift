import Foundation
import Testing
@testable import DJKit

@Suite("Aggiornamento degli strumenti")
struct ToolsUpdaterTests {

    private func makeLibrary() throws -> LibraryPaths {
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "CrateTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        let paths = LibraryPaths(root: root)
        try paths.createDirectories()
        return paths
    }

    @Test("Si prende la variante a cartella, non il binario singolo")
    func picksTheOnedirAsset() {
        // Il binario singolo è un PyInstaller *onefile*: si riespande a ogni lancio e costa 13
        // secondi di avvio per invocazione contro 0,33 della cartella. Se qualcuno "semplifica"
        // cambiando questa costante, l'app torna lenta senza che nulla appaia rotto.
        #expect(ToolsUpdater.assetName == "yt-dlp_macos.zip")
        #expect(ToolsUpdater.executableName == "yt-dlp_macos")
    }

    @Test("Un archivio senza l'eseguibile atteso non viene installato")
    func refusesArchiveWithoutExecutable() async throws {
        let paths = try makeLibrary()
        defer { try? FileManager.default.removeItem(at: paths.root) }

        // Un archivio valido ma con dentro la cosa sbagliata: deve fallire con un errore chiaro,
        // non lasciare mezza installazione.
        let workingDirectory = paths.scratchDirectory.appending(path: "fake", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        let payload = workingDirectory.appending(path: "qualcosaltro")
        try Data("non sono yt-dlp".utf8).write(to: payload)

        let archive = workingDirectory.appending(path: ToolsUpdater.assetName)
        let zipped = try await ProcessRunner.run(
            executable: URL(filePath: "/usr/bin/ditto"),
            arguments: ["-c", "-k", payload.path, archive.path]
        )
        #expect(zipped.didSucceed)

        let updater = ToolsUpdater(paths: paths)
        await #expect(throws: ToolsUpdateError.self) {
            try await updater.install(archive: archive)
        }
        // Niente cartella `yt-dlp` mezza scritta lasciata in giro.
        let installed = paths.toolsDirectory.appending(path: ToolsUpdater.installedDirectoryName)
        #expect(!FileManager.default.fileExists(atPath: installed.path))
    }
}

/// Test che scaricano davvero da GitHub. Esclusi dalla suite normale: sono 124 MB e dipendono da
/// una release che cambia.
///
///     CRATE_NETWORK_TESTS=1 swift test --package-path DJKit --filter ToolsUpdaterIntegration
@Suite("Aggiornamento — integrazione")
struct ToolsUpdaterIntegrationTests {
    private static var networkEnabled: Bool {
        ProcessInfo.processInfo.environment["CRATE_NETWORK_TESTS"] != nil
    }

    @Test(
        "L'ultima release si scarica, si spacchetta e il binario installato risponde",
        .enabled(if: ToolsUpdaterIntegrationTests.networkEnabled),
        .timeLimit(.minutes(5))
    )
    func downloadsAndInstalls() async throws {
        // **Radice temporanea**: la libreria vera di Gabriel non si tocca per provare qualcosa.
        let root = URL(filePath: NSTemporaryDirectory())
            .appending(path: "CrateTools-\(UUID().uuidString)", directoryHint: .isDirectory)
        let paths = LibraryPaths(root: root)
        try paths.createDirectories()
        defer { try? FileManager.default.removeItem(at: root) }

        let updater = ToolsUpdater(paths: paths)
        let result = try await updater.update()
        #expect(!result.version.isEmpty)

        let executable = result.installedAt.appending(path: ToolsUpdater.executableName)
        #expect(FileManager.default.isExecutableFile(atPath: executable.path))
        // La cartella `_internal/` è ciò che distingue la onedir dal binario singolo.
        #expect(FileManager.default.fileExists(atPath: result.installedAt.appending(path: "_internal").path))

        // E soprattutto: parte e dice la sua versione.
        let locator = ToolLocator(updatedDirectory: paths.toolsDirectory, bundledDirectory: nil)
        let version = await ToolsUpdater.installedVersion(locator: locator)
        #expect(version != nil)
    }
}
