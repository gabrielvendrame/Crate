import Foundation
import GRDB

/// Un'etichetta che l'utente si definisce da sé — «disco», «funky», «da ricomprare» — e che serve
/// a **ritrovare i dischi in cassa**.
///
/// È l'unica eccezione al confine dei quattro metadati scritto in `CLAUDE.md`, chiesta da Gabriel
/// il 2026-09-05, e la differenza non è formale: genere, anno e rating sarebbero campi fissi
/// decisi da noi, i tag sono una dimensione che se la definisce chi usa l'app. Se non ne crea
/// nessuno, la libreria resta esattamente com'era.
///
/// `position` esiste per lo stesso motivo per cui esiste nelle scalette: l'ordine dei tag lo
/// decide l'utente — i due o tre che usa di continuo in cima — e l'ordine alfabetico non lo
/// rispetterebbe.
public struct Tag: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    /// Indice nella tavolozza dei cue, riusata per non avere due serie di colori nella stessa app.
    public var colorIndex: Int
    public var position: Int

    public init(
        id: String = UUID().uuidString,
        name: String,
        colorIndex: Int = 0,
        position: Int = 0
    ) {
        self.id = id
        self.name = name
        self.colorIndex = colorIndex
        self.position = position
    }

    /// Come si scrive un nome di tag: senza spazi ai bordi, e mai vuoto.
    ///
    /// Sta qui e non nella vista perché la stessa ripulitura serve a chi crea un tag dal menu
    /// contestuale, a chi lo rinomina dalla barra laterale e al confronto che impedisce i
    /// doppioni: tre punti che devono concordare.
    public static func normalized(name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension Tag: FetchableRecord, MutablePersistableRecord {
    public static let databaseTableName = "tag"

    public enum Columns {
        public static let id = Column("id")
        public static let name = Column("name")
        public static let position = Column("position")
    }
}
