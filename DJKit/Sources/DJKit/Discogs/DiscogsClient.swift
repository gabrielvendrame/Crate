import Foundation

public enum DiscogsError: LocalizedError {
    case missingToken
    case invalidToken
    case rateLimited
    case httpStatus(Int)
    case transport(String)
    case malformedResponse

    public var errorDescription: String? {
        switch self {
        case .missingToken:
            "Manca il token di Discogs: incollalo in «Aggiungi da YouTube → Discogs»."
        case .invalidToken:
            "Discogs ha rifiutato il token: controlla di averlo copiato per intero."
        case .rateLimited:
            "Discogs ha messo un limite alle richieste: riprova fra un minuto."
        case .httpStatus(let code):
            "Discogs ha risposto \(code)."
        case .transport(let detail):
            "Non riesco a raggiungere Discogs: \(detail)"
        case .malformedResponse:
            "La risposta di Discogs non è nel formato atteso."
        }
    }
}

/// Il minimo che serve delle API di Discogs: cercare edizioni e scaricarne la copertina.
///
/// **Richiede un token personale**, ed è il motivo per cui il confine «nessun account» di
/// `CLAUDE.md` si è spostato: senza autenticazione Discogs non restituisce gli URL delle immagini,
/// che sono esattamente la cosa che serve. Il token lo genera Gabriel dal suo profilo e lo incolla
/// nell'app; non esce da questa macchina se non verso `api.discogs.com`.
public struct DiscogsClient: Sendable {
    /// Discogs chiede uno User-Agent che identifichi l'applicazione, e rifiuta quelli generici.
    static let userAgent = "Crate/1.0 (+local vinyl set preparation tool)"
    static let searchEndpoint = URL(string: "https://api.discogs.com/database/search")!

    private let token: String
    private let session: URLSession

    public init(token: String, session: URLSession = .shared) {
        self.token = token
        self.session = session
    }

    /// Esegue i tentativi in ordine e restituisce i risultati del primo che ne produce.
    ///
    /// Si ferma al primo con risultati invece di unirli tutti: i tentativi sono ordinati dal più
    /// preciso al più largo, e mescolarli metterebbe accanto al disco giusto altri nove omonimi.
    public func search(
        attempts: [DiscogsQuery.Attempt],
        limit: Int = 12
    ) async throws -> [DiscogsRelease] {
        for attempt in attempts {
            let releases = try await search(attempt, limit: limit)
            if !releases.isEmpty { return releases }
        }
        return []
    }

    public func search(
        _ attempt: DiscogsQuery.Attempt,
        limit: Int = 12
    ) async throws -> [DiscogsRelease] {
        var components = URLComponents(url: Self.searchEndpoint, resolvingAgainstBaseURL: false)!
        var items = attempt.parameters.map { URLQueryItem(name: $0.key, value: $0.value) }
        items.append(URLQueryItem(name: "type", value: "release"))
        items.append(URLQueryItem(name: "per_page", value: String(limit)))
        if attempt.vinylOnly {
            items.append(URLQueryItem(name: "format", value: "Vinyl"))
        }
        // Ordine stabile: senza, due esecuzioni identiche producono URL diversi e il confronto nei
        // test diventa un terno al lotto.
        components.queryItems = items.sorted { $0.name < $1.name }

        let data = try await get(components.url!)
        return try Self.decodeSearch(data)
    }

    /// Scarica un'immagine di copertina.
    ///
    /// Passa dallo stesso client e con le stesse intestazioni: le immagini di Discogs stanno su un
    /// dominio suo che rifiuta le richieste senza User-Agent.
    public func imageData(from url: URL) async throws -> Data {
        try await get(url)
    }

    // MARK: - Trasporto

    private func get(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Discogs token=\(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw DiscogsError.transport(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { return data }
        switch http.statusCode {
        case 200..<300: return data
        case 401, 403: throw DiscogsError.invalidToken
        case 429: throw DiscogsError.rateLimited
        default: throw DiscogsError.httpStatus(http.statusCode)
        }
    }

    // MARK: - Decodifica

    /// Separata dal trasporto perché è la parte che si può provare senza rete, su una risposta
    /// vera salvata a mano.
    static func decodeSearch(_ data: Data) throws -> [DiscogsRelease] {
        struct Payload: Decodable {
            struct Result: Decodable {
                let id: Int
                let title: String
                let year: String?
                let label: [String]?
                let catno: String?
                let format: [String]?
                let country: String?
                let thumb: String?
                let coverImage: String?

                enum CodingKeys: String, CodingKey {
                    case id, title, year, label, catno, format, country, thumb
                    case coverImage = "cover_image"
                }
            }
            let results: [Result]
        }

        let payload: Payload
        do {
            payload = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw DiscogsError.malformedResponse
        }

        return payload.results.map { result in
            DiscogsRelease(
                id: result.id,
                title: result.title,
                year: result.year,
                label: result.label?.first,
                catalogNumber: result.catno,
                formats: result.format ?? [],
                country: result.country,
                // Discogs manda stringhe vuote quando l'immagine non c'è, e `URL(string: "")` è
                // `nil` ma `URL(string: " ")` no: meglio filtrare prima.
                thumbnailURL: Self.url(result.thumb),
                coverURL: Self.url(result.coverImage)
            )
        }
    }

    private static func url(_ value: String?) -> URL? {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return URL(string: value)
    }
}
