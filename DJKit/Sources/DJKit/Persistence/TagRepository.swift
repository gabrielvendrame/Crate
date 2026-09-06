import Foundation
import GRDB

/// Letture e scritture sui tag e sui loro legami con le tracce.
///
/// Separato da `TrackRepository` e non aggiunto in fondo a quello: i tag si leggono per conto
/// loro — la barra laterale li mostra anche quando nessuna traccia è selezionata — e tenerli
/// insieme alle tracce avrebbe mischiato due osservazioni che si aggiornano in momenti diversi.
public struct TagRepository: Sendable {
    private let database: AppDatabase

    public init(database: AppDatabase) {
        self.database = database
    }

    // MARK: - Tag

    public func allTags() async throws -> [Tag] {
        try await database.reader.read { db in try Self.fetchAll(db) }
    }

    /// Crea un tag, oppure restituisce quello che porta già quel nome.
    ///
    /// **Idempotente di proposito**: il tag si crea scrivendone il nome dal menu contestuale di
    /// una traccia, e scrivere due volte «disco» vuol dire volerci mettere quel disco lì — non
    /// aprire un avviso di errore. La rinomina invece rifiuta la collisione, perché lì il nome
    /// esistente non è quello che si voleva.
    public func createTag(name: String, colorIndex: Int? = nil) async throws -> Tag {
        guard let name = Tag.normalized(name: name) else { throw TagError.emptyName }
        return try await database.writer.write { db in
            if let existing = try Tag.filter(Tag.Columns.name == name).fetchOne(db) {
                return existing
            }
            let count = try Tag.fetchCount(db)
            let nextPosition = try Int.fetchOne(
                db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM tag"
            ) ?? 0
            var tag = Tag(
                name: name,
                // Un colore diverso dal precedente senza doverlo scegliere: chi crea un tag sta
                // pensando al disco che ha in mano, non alla tavolozza.
                colorIndex: colorIndex ?? count,
                position: nextPosition
            )
            try tag.insert(db)
            return tag
        }
    }

    /// Rinomina o ricolora un tag. Il nome già preso da un altro tag fa fallire la scrittura, con
    /// un errore che si può mostrare invece di fondere due tag di nascosto.
    public func save(_ tag: Tag) async throws {
        guard let name = Tag.normalized(name: tag.name) else { throw TagError.emptyName }
        let tag = tag
        try await database.writer.write { db in
            // La copia mutabile vive dentro la closure: Swift 6 non ammette di catturare una
            // `var` esterna in codice che gira su un altro thread.
            var updated = tag
            updated.name = name
            let clash = try Tag
                .filter(Tag.Columns.name == name && Tag.Columns.id != updated.id)
                .fetchOne(db)
            if let clash { throw TagError.duplicateName(clash.name) }
            try updated.update(db)
        }
    }

    public func deleteTag(id: String) async throws {
        _ = try await database.writer.write { db in
            try Tag.deleteOne(db, key: id)
        }
    }

    /// Riscrive `position` in modo denso su tutti i tag, come per le scalette: sono pochi, e così
    /// non c'è nessuna deriva da rimediare più avanti.
    public func reorderTags(idsInOrder: [String]) async throws {
        try await database.writer.write { db in
            for (index, id) in idsInOrder.enumerated() {
                try db.execute(
                    sql: "UPDATE tag SET position = ? WHERE id = ?",
                    arguments: [index, id]
                )
            }
        }
    }

    public func observeAllTags() -> ValueObservation<ValueReducers.Fetch<[Tag]>> {
        ValueObservation.tracking { db in try Self.fetchAll(db) }
    }

    private static func fetchAll(_ db: Database) throws -> [Tag] {
        try Tag.order(Tag.Columns.position, Tag.Columns.name).fetchAll(db)
    }

    // MARK: - Legami

    /// I tag di ogni traccia, in una mappa sola.
    ///
    /// Non una query per traccia: la libreria è di decine di brani e la tabella ponte è piccola,
    /// quindi leggerla intera costa meno di una query per riga e dà alla vista una struttura già
    /// pronta da interrogare mentre disegna.
    public func tagIDsByTrack() async throws -> [String: Set<String>] {
        try await database.reader.read { db in try Self.fetchTagIDsByTrack(db) }
    }

    public func observeTagIDsByTrack()
        -> ValueObservation<ValueReducers.Fetch<[String: Set<String>]>> {
        ValueObservation.tracking { db in try Self.fetchTagIDsByTrack(db) }
    }

    private static func fetchTagIDsByTrack(_ db: Database) throws -> [String: Set<String>] {
        let links = try TrackTag.fetchAll(db)
        return links.reduce(into: [String: Set<String>]()) { result, link in
            result[link.trackID, default: []].insert(link.tagID)
        }
    }

    /// Mette il tag su tutte le tracce indicate. Quelle che ce l'hanno già restano come sono.
    public func addTag(id tagID: String, toTracks trackIDs: [String]) async throws {
        guard !trackIDs.isEmpty else { return }
        try await database.writer.write { db in
            for trackID in trackIDs {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO trackTag (trackID, tagID) VALUES (?, ?)",
                    arguments: [trackID, tagID]
                )
            }
        }
    }

    public func removeTag(id tagID: String, fromTracks trackIDs: [String]) async throws {
        guard !trackIDs.isEmpty else { return }
        try await database.writer.write { db in
            try db.execute(
                sql: """
                    DELETE FROM trackTag
                    WHERE tagID = ? AND trackID IN (\(databaseQuestionMarks(count: trackIDs.count)))
                    """,
                arguments: StatementArguments([tagID] + trackIDs)
            )
        }
    }

    /// Sostituisce in blocco i tag di una traccia: è ciò che serve all'ispettore, dove si
    /// spuntano e si tolgono le caselle di una traccia sola.
    public func setTags(ids tagIDs: Set<String>, forTrack trackID: String) async throws {
        try await database.writer.write { db in
            try db.execute(
                sql: "DELETE FROM trackTag WHERE trackID = ?",
                arguments: [trackID]
            )
            for tagID in tagIDs {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO trackTag (trackID, tagID) VALUES (?, ?)",
                    arguments: [trackID, tagID]
                )
            }
        }
    }
}

public enum TagError: LocalizedError, Equatable {
    case emptyName
    case duplicateName(String)

    public var errorDescription: String? {
        switch self {
        case .emptyName:
            "Un tag deve avere un nome."
        case .duplicateName(let name):
            "Esiste già un tag «\(name)»."
        }
    }
}
