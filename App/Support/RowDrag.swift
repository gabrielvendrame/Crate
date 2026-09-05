import CoreTransferable
import UniformTypeIdentifiers

/// Il carico di un trascinamento che parte da una traccia: una riga della libreria.
///
/// Un tipo suo invece della semplice stringa dell'identificativo, così un testo qualsiasi
/// trascinato dentro l'app non viene scambiato per un brano. La seconda rappresentazione, come
/// testo semplice, serve a chi si aspetta comunque una stringa.
struct RowDrag: Codable, Transferable {
    var trackID: String?

    var plainText: String { trackID ?? "" }

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .json)
        ProxyRepresentation(exporting: \.plainText)
    }
}
