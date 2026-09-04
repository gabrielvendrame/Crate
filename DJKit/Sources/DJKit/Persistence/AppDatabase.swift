import Foundation
import GRDB

/// Punto d'accesso unico al database della libreria.
///
/// Le migrazioni vengono applicate alla costruzione: se `AppDatabase` esiste, lo schema è
/// aggiornato.
public final class AppDatabase: Sendable {
    public let writer: any DatabaseWriter
    public var reader: any DatabaseReader { writer }

    public init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try Migrations.migrator.migrate(writer)
    }

    /// Apre (o crea) il database della libreria su disco.
    public static func open(at url: URL) throws -> AppDatabase {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let pool = try DatabasePool(path: url.path, configuration: configuration)
        return try AppDatabase(writer: pool)
    }

    /// Database volatile per i test: stesso schema, nessun file.
    public static func inMemory() throws -> AppDatabase {
        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: configuration)
        return try AppDatabase(writer: queue)
    }
}
