import AppKit
import Foundation
import GRDB
import Observation
import DJKit

/// Cosa è selezionato nella barra laterale.
enum SidebarSelection: Hashable {
    case library
    case playlist(String)
}

/// Stato condiviso dell'applicazione: database aperto, repository, coda di import e le liste che
/// alimentano la UI.
///
/// Le liste si aggiornano da sole tramite `ValueObservation`: nessuna vista deve ricaricare a mano
/// dopo una scrittura.
@MainActor
@Observable
final class AppModel {
    /// **L'unica istanza, raggiunta direttamente dalle viste invece che dall'`environment`.**
    ///
    /// Non è una scorciatoia: `@Environment(AppModel.self)` in questa app **fa cadere il
    /// processo**, e per un motivo strutturale. Su macOS diversi pezzi di interfaccia vivono in
    /// una `NSHostingView` propria — la toolbar, l'ispettore, i fogli, i popover — e quando uno di
    /// quei pezzi scrive nel modello, SwiftUI rivaluta il `body` del proprietario **dentro
    /// l'hosting view secondaria**, dove l'ambiente iniettato alla radice della scena non c'è.
    /// Il property wrapper allora chiama `fatalError`, e non c'è modo di intercettarlo.
    ///
    /// Misurato: bastava scrivere un carattere nel campo di ricerca in toolbar. Reiniettare
    /// `.environment(model)` sui contenuti ospitati copre un caso alla volta e ne lascia scoperti
    /// altri — è la toppa che era già stata messa all'ispettore il 2026-09-04, e che qui non
    /// bastava più. Con un riferimento diretto il problema non esiste: l'osservazione di
    /// `@Observable` funziona sulla **lettura della proprietà**, non su come si è ottenuto
    /// l'oggetto, quindi le viste continuano ad aggiornarsi come prima.
    ///
    /// Il prezzo è che il modello non è più sostituibile per una preview o un test di interfaccia.
    /// In questo progetto non è un prezzo: i test coprono la logica in `DJKit`, e di preview non
    /// ce ne sono.
    static let shared = AppModel()

    private(set) var paths: LibraryPaths?
    private(set) var database: AppDatabase?
    private(set) var tracks: TrackRepository?
    private(set) var playlists: PlaylistRepository?
    private(set) var importQueue: ImportQueue?
    private(set) var analyzer: TrackAnalyzer?
    private(set) var toolLocator: ToolLocator?
    /// Il grafo audio. `nil` solo se l'uscita non si è potuta configurare: in quel caso la
    /// libreria resta usabile e sono i deck a restare muti.
    private(set) var audioGraph: AudioGraph?

    /// I due deck, impilati in fondo alla finestra: A sopra, B sotto.
    let deckA = DeckState(slot: .a)
    let deckB = DeckState(slot: .b)

    /// Il deck su cui agiscono i tasti `1`–`8`. Due deck e una tastiera sola: senza un deck
    /// "attivo" le scorciatoie non saprebbero a chi parlare. Cambia caricando una traccia o
    /// toccando un controllo di quel deck, e si vede dalla barra accesa sul suo bordo.
    private(set) var focusedDeckSlot: DeckState.Slot = .a

    private var keyMonitor: DeckKeyMonitor?

    /// Altezza della fascia dei deck, decisa trascinando la maniglia e ricordata fra un avvio e
    /// l'altro. È un numero nostro e non una divisione calcolata da `VSplitView`, che cambiando
    /// vista la rifaceva a modo suo.
    var deckBarHeight: Double {
        get { storedDeckBarHeight }
        set {
            storedDeckBarHeight = min(max(300, newValue), 700)
            UserDefaults.standard.set(storedDeckBarHeight, forKey: "deckBarHeight")
        }
    }

    private var storedDeckBarHeight: Double =
        UserDefaults.standard.object(forKey: "deckBarHeight") as? Double ?? 400

    /// Come stanno i due deck nella fascia.
    ///
    /// **L'impilata resta il predefinito**, e non è una preferenza estetica: affiancandoli ogni
    /// waveform ha metà larghezza, cioè metà della risoluzione temporale che serve proprio per
    /// decidere dove attaccare. L'alternativa esiste perché l'ha chiesta Gabriel il 2026-09-04,
    /// non perché sia equivalente. Le waveform restano orizzontali in tutti e due i casi.
    enum DeckLayout: String, CaseIterable {
        case stacked
        case sideBySide

        var label: String {
            switch self {
            case .stacked: "Impilati"
            case .sideBySide: "Affiancati"
            }
        }
    }

    var deckLayout: DeckLayout {
        get { storedDeckLayout }
        set {
            storedDeckLayout = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "deckLayout")
        }
    }

    private var storedDeckLayout: DeckLayout =
        UserDefaults.standard.string(forKey: "deckLayout")
            .flatMap(DeckLayout.init(rawValue:)) ?? .stacked

    func toggleDeckLayout() {
        deckLayout = deckLayout == .stacked ? .sideBySide : .stacked
    }

    /// Posizione del crossfader: 0 tutto sul deck A, 1 tutto sul B, 0,5 entrambi.
    ///
    /// Copia osservabile di `AudioGraph.crossfader`, che vive fuori da `@Observable`. Il fermo al
    /// centro sta qui e non nella vista: vale per qualunque cosa lo muova.
    var crossfader: Double {
        get { storedCrossfader }
        set {
            let clamped = min(max(0, newValue), 1)
            storedCrossfader = abs(clamped - 0.5) < 0.03 ? 0.5 : clamped
            audioGraph?.crossfader = storedCrossfader
        }
    }

    private var storedCrossfader: Double = 0.5

    /// Il quantize: acceso, i cue si agganciano alla battuta più vicina della griglia.
    ///
    /// **Uno solo per tutta l'app, non uno per deck.** Sui CDJ è per lettore, ma lì si sta
    /// suonando davanti a un pubblico e capita di volerlo spento solo di là; qui si prepara, e due
    /// interruttori identici a due centimetri di distanza sarebbero solo un modo di non ricordare
    /// più quale dei due si è toccato.
    var isQuantizeEnabled: Bool {
        get { storedQuantizeEnabled }
        set {
            storedQuantizeEnabled = newValue
            UserDefaults.standard.set(newValue, forKey: "quantizeEnabled")
            applyQuantizeToDecks()
        }
    }

    var quantizeResolution: QuantizeResolution {
        get { storedQuantizeResolution }
        set {
            storedQuantizeResolution = newValue
            UserDefaults.standard.set(newValue.rawValue, forKey: "quantizeResolution")
            applyQuantizeToDecks()
        }
    }

    private var storedQuantizeEnabled: Bool =
        UserDefaults.standard.object(forKey: "quantizeEnabled") as? Bool ?? true

    private var storedQuantizeResolution: QuantizeResolution =
        (UserDefaults.standard.string(forKey: "quantizeResolution"))
            .flatMap(QuantizeResolution.init(rawValue:)) ?? .beat

    private func applyQuantizeToDecks() {
        for deck in [deckA, deckB] {
            deck.isQuantizeEnabled = storedQuantizeEnabled
            deck.quantizeResolution = storedQuantizeResolution
        }
    }

    /// Se l'apertura della libreria fallisce lo diciamo, invece di mostrare un'app vuota e muta.
    private(set) var startupError: String?
    /// Errori recuperabili durante l'uso (foto illeggibile, salvataggio fallito).
    var transientError: String?

    var trackList: [Track] = []
    /// Ricerca e sottoinsieme scelti nella libreria. Il testo lo scrive `.searchable`, il
    /// sottoinsieme il menu del filtro.
    var libraryFilter = LibraryFilter()
    var playlistList: [Playlist] = []
    var selection: SidebarSelection? = .library
    var selectedTrackIDs: Set<String> = []
    var isImportSheetPresented = false
    var isToolsSheetPresented = false
    var isShortcutsSheetPresented = false
    var isInspectorPresented = true
    /// Tracce su cui è in corso un ricalcolo manuale della waveform.
    private(set) var analyzingTrackIDs: Set<String> = []

    private var observers: [AnyDatabaseCancellable] = []

    init() {
        do {
            let paths = try LibraryPaths.standard()
            try paths.createDirectories()
            try paths.clearScratch()
            let database = try AppDatabase.open(at: paths.databaseURL)
            let trackRepository = TrackRepository(database: database)
            let locator = ToolLocator(paths: paths)

            self.toolLocator = locator
            self.paths = paths
            self.database = database
            self.tracks = trackRepository
            self.playlists = PlaylistRepository(database: database)
            self.analyzer = TrackAnalyzer(paths: paths, repository: trackRepository)
            self.importQueue = ImportQueue(
                runner: YtDlpRunner(locator: locator),
                converter: AudioConverter(locator: locator),
                repository: trackRepository,
                paths: paths
            )
            startObserving(database: database)
        } catch {
            startupError = Self.describe(error)
        }

        if let paths, let tracks {
            for deck in [deckA, deckB] {
                deck.configure(paths: paths, repository: tracks)
                deck.reportError = { [weak self] message in self?.transientError = message }
            }
        }

        // Il grafo audio si crea a parte: un device di uscita che manca non deve impedire di
        // importare e catalogare, che sono metà del lavoro.
        do {
            let graph = try AudioGraph()
            audioGraph = graph
            deckA.attach(engine: graph.makeDeck())
            deckB.attach(engine: graph.makeDeck())
        } catch {
            transientError = Self.describe(error)
        }

        applyQuantizeToDecks()

        keyMonitor = DeckKeyMonitor { [weak self] action, phase, isShifted in
            self?.handle(action, phase: phase, isShifted: isShifted)
        }
        keyMonitor?.install()
    }

    private func startObserving(database: AppDatabase) {
        guard let tracks, let playlists else { return }

        observers.append(
            tracks.observeAllTracks().start(
                in: database.reader,
                onError: { [weak self] error in
                    self?.transientError = "La libreria non si aggiorna: \(Self.describe(error))"
                },
                onChange: { [weak self] value in
                    self?.trackList = value
                    // I deck tengono una copia della traccia caricata: senza questa riga
                    // continuerebbero a mostrare i metadati di quando è stata caricata e a
                    // quantizzare su un BPM vecchio.
                    self?.deckA.refreshTrack(from: value)
                    self?.deckB.refreshTrack(from: value)
                }
            )
        )
        observers.append(
            playlists.observeAllPlaylists().start(
                in: database.reader,
                onError: { [weak self] error in
                    self?.transientError = "Le scalette non si aggiornano: \(Self.describe(error))"
                },
                onChange: { [weak self] value in self?.playlistList = value }
            )
        )
    }

    // MARK: - Selezione

    var selectedPlaylist: Playlist? {
        guard case .playlist(let id) = selection else { return nil }
        return playlistList.first { $0.id == id }
    }

    /// La libreria come la vede la tabella: filtrata, non ordinata — l'ordinamento è della
    /// vista, che ha le sue intestazioni di colonna.
    var filteredTracks: [Track] {
        libraryFilter.apply(to: trackList)
    }

    /// L'ispettore lavora su una traccia sola: con selezione multipla non mostra nulla.
    var selectedTrack: Track? {
        guard selectedTrackIDs.count == 1, let id = selectedTrackIDs.first else { return nil }
        return trackList.first { $0.id == id }
    }

    // MARK: - Tracce

    func save(track: Track) {
        guard let tracks else { return }
        Task {
            do { try await tracks.save(track) }
            catch { transientError = "Salvataggio non riuscito: \(error.localizedDescription)" }
        }
    }

    /// Corregge il BPM di una traccia dalla libreria, lasciando il downbeat dov'è.
    ///
    /// `nil` toglie la griglia insieme al BPM: un downbeat senza tempo non definisce niente.
    /// Il deck su cui la traccia è caricata si aggiorna da sé, dall'osservazione della libreria.
    func setBPM(_ bpm: Double?, for track: Track) {
        guard let tracks else { return }
        let offset = bpm == nil ? nil : track.beatgridOffsetSeconds
        Task {
            do {
                try await tracks.updateBeatgrid(
                    trackID: track.id,
                    bpm: bpm,
                    beatgridOffsetSeconds: offset
                )
            } catch {
                transientError = "Non ho potuto salvare il BPM: \(error.localizedDescription)"
            }
        }
    }

    /// Le tracce che una conferma di eliminazione sta aspettando. Vuoto = nessuna conferma
    /// aperta.
    ///
    /// **L'eliminazione si conferma sempre**, anche per una traccia sola: porta via un file audio
    /// che è costato minuti di download, e non c'è un annulla — il file sparisce dal disco.
    var pendingDeletion: [Track] = []

    func requestDeletion(of trackIDs: Set<String>) {
        let ordered = trackList.filter { trackIDs.contains($0.id) }
        guard !ordered.isEmpty else { return }
        pendingDeletion = ordered
    }

    func requestDeletion(of track: Track) {
        pendingDeletion = [track]
    }

    /// Quanto spazio su disco libera l'eliminazione in attesa: è il numero che fa decidere.
    var pendingDeletionBytes: Int64 {
        guard let paths else { return 0 }
        return pendingDeletion.reduce(0) { total, track in
            total + Self.fileSizes(of: track, paths: paths).reduce(0, +)
        }
    }

    func confirmPendingDeletion() {
        let tracks = pendingDeletion
        pendingDeletion = []
        for track in tracks { deleteTrack(track) }
    }

    /// Elimina la traccia e i file che le appartengono. I cue point spariscono a cascata dal
    /// database; audio, peaks e foto vanno rimossi a mano perché stanno sul disco.
    func deleteTrack(_ track: Track) {
        guard let tracks, let paths else { return }
        let filesToRemove = Self.fileURLs(of: track, paths: paths)

        Task {
            do {
                try await tracks.deleteTrack(id: track.id)
                selectedTrackIDs.remove(track.id)
                if deckA.track?.id == track.id { deckA.clear() }
                if deckB.track?.id == track.id { deckB.clear() }
                for url in filesToRemove {
                    try? FileManager.default.removeItem(at: url)
                }
            } catch {
                transientError = "Eliminazione non riuscita: \(Self.describe(error))"
            }
        }
    }

    /// Tutti i file che appartengono a una traccia: audio, cache dei peaks e le due foto.
    private static func fileURLs(of track: Track, paths: LibraryPaths) -> [URL] {
        [
            track.audioFilename.map { paths.audioURL(filename: $0) },
            track.peaksFilename.map { paths.peaksURL(filename: $0) },
            track.labelImageAFilename.map { paths.artworkURL(filename: $0) },
            track.labelImageBFilename.map { paths.artworkURL(filename: $0) },
        ].compactMap(\.self)
    }

    private static func fileSizes(of track: Track, paths: LibraryPaths) -> [Int64] {
        fileURLs(of: track, paths: paths).compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey])
            return values?.fileSize.map(Int64.init)
        }
    }

    /// Il messaggio da mostrare per un errore.
    ///
    /// `String(describing:)` su un errore di GRDB stampa la struttura interna del tipo — utile a
    /// chi legge un log, illeggibile in un avviso. `errorDescription` è la frase scritta apposta,
    /// e i nostri errori ce l'hanno tutti.
    static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    // MARK: - Deck

    func deck(_ slot: DeckState.Slot) -> DeckState {
        slot == .a ? deckA : deckB
    }

    /// Carica una traccia su un deck. Senza waveform calcolata il deck lo dice invece di restare
    /// vuoto senza spiegazioni: il ricalcolo è a un clic di distanza dalla libreria.
    func load(_ track: Track, on slot: DeckState.Slot) {
        let deck = deck(slot)
        // Chi carica vuole lavorare su quel deck: il fuoco lo segue.
        focus(slot)
        Task { await deck.load(track: track, analyzer: analyzer) }
    }

    func focus(_ slot: DeckState.Slot) {
        focusedDeckSlot = slot
    }

    /// Il deck che ha il fuoco cambia, e con lui a chi parlano i tasti.
    func toggleFocusedDeck() {
        focusedDeckSlot = focusedDeckSlot == .a ? .b : .a
    }

    /// Quale deck ha chiesto di aprire l'editor della griglia. La fascia dei deck lo osserva e
    /// apre il popover; azzerarlo subito dopo è compito suo.
    var gridEditorRequest: DeckState.Slot?

    /// Traduce un tasto in un comando del deck attivo.
    ///
    /// Sta qui e non nel monitor perché il monitor conosce solo la tastiera: quale deck sia
    /// quello attivo, e cosa significhi «nudge» per lui, lo sa il modello.
    private func handle(_ action: DeckKeyMonitor.Action, phase: DeckKeyMonitor.Phase, isShifted: Bool) {
        let deck = deck(focusedDeckSlot)

        switch action {
        case .hotCue(let slot):
            guard phase == .down else { return }
            if isShifted { deck.deleteHotCue(slot: slot) } else { deck.pressHotCue(slot: slot) }

        case .togglePlay:
            guard phase == .down else { return }
            deck.togglePlay()

        case .cue:
            switch phase {
            case .down: deck.pressCue()
            case .held: break
            case .up: deck.releaseCue()
            }

        case .nudge(let forward):
            // Un colpo alla pressione, la spinta quando il tasto resta giù: gli stessi due gesti
            // del pulsante, che sono i due modi diversi di mettere in fase.
            switch phase {
            case .down: deck.nudge(forward: forward)
            case .held: deck.startBend(forward: forward)
            case .up: deck.endBend()
            }

        case .switchDeck:
            guard phase == .down else { return }
            toggleFocusedDeck()

        case .beatgrid:
            guard phase == .down else { return }
            gridEditorRequest = focusedDeckSlot

        case .zoom(let closer):
            guard phase == .down else { return }
            deck.zoom(byFactor: closer ? 2 : 0.5)
        }
    }

    // MARK: - Analisi

    func isAnalyzing(_ track: Track) -> Bool {
        analyzingTrackIDs.contains(track.id)
    }

    /// Ricalcola la waveform di una traccia già in libreria.
    ///
    /// Serve alle tracce importate prima che l'analisi esistesse e a quelle il cui file `.peaks`
    /// è stato cancellato o è illeggibile.
    func reanalyze(_ track: Track) {
        guard let analyzer, !analyzingTrackIDs.contains(track.id) else { return }
        analyzingTrackIDs.insert(track.id)
        Task {
            defer { analyzingTrackIDs.remove(track.id) }
            do {
                let updated = try await analyzer.analyze(track: track)
                await deckA.reloadPeaks(track: updated, analyzer: analyzer)
                await deckB.reloadPeaks(track: updated, analyzer: analyzer)
            } catch {
                transientError = (error as? LocalizedError)?.errorDescription
                    ?? error.localizedDescription
            }
        }
    }

    /// Le tracce a cui manca la waveform **oppure** il BPM: l'analisi produce entrambi in una
    /// passata sola, quindi non ha senso distinguere due elenchi.
    var tracksWithoutAnalysis: [Track] {
        trackList.filter {
            $0.audioFilename != nil && ($0.peaksFilename == nil || $0.bpm == nil)
        }
    }

    /// Analizza in fila tutte le tracce a cui manca qualcosa.
    ///
    /// In fila e non in parallelo: ogni analisi tiene in RAM la traccia decodificata per intero —
    /// oltre 100 MB — e farne partire dieci insieme svuoterebbe la memoria senza finire prima.
    func analyzeTracksWithoutAnalysis() {
        guard let analyzer else { return }
        let pending = tracksWithoutAnalysis.filter { !analyzingTrackIDs.contains($0.id) }
        guard !pending.isEmpty else { return }

        analyzingTrackIDs.formUnion(pending.map(\.id))
        Task {
            for track in pending {
                defer { analyzingTrackIDs.remove(track.id) }
                do {
                    let updated = try await analyzer.analyze(track: track)
                    await deckA.reloadPeaks(track: updated, analyzer: analyzer)
                    await deckB.reloadPeaks(track: updated, analyzer: analyzer)
                } catch {
                    // Una traccia rotta non deve fermare le altre: il motivo resta sulla riga,
                    // che la tabella mostra come stato "Errore".
                    continue
                }
            }
        }
    }

    // MARK: - Aggiornamento di yt-dlp

    /// A che punto è l'aggiornamento di yt-dlp.
    ///
    /// Serve uno stato e non un semplice booleano: il download è di 124 MB e dura un minuto, e
    /// senza il progresso l'unica cosa che si può mostrare è una rotella che non dice niente.
    enum ToolsUpdateState: Equatable {
        case idle
        case running(Double)
        case succeeded(String)
        case failed(String)
    }

    private(set) var toolsUpdateState: ToolsUpdateState = .idle
    /// La versione che si sta usando adesso, chiesta al binario stesso.
    private(set) var installedYtDlpVersion: String?

    func refreshInstalledYtDlpVersion() {
        guard let toolLocator else { return }
        Task {
            installedYtDlpVersion = await ToolsUpdater.installedVersion(locator: toolLocator)
        }
    }

    /// Scarica l'ultima release di yt-dlp e la installa fra gli strumenti aggiornati.
    ///
    /// Serve più spesso di quanto sembri: YouTube cambia e la copia impacchettata smette di
    /// scaricare, di solito con un errore che non dice che è colpa della versione.
    func updateYtDlp() {
        guard let paths else { return }
        if case .running = toolsUpdateState { return }

        toolsUpdateState = .running(0)
        Task {
            do {
                let result = try await ToolsUpdater(paths: paths).update { fraction in
                    Task { @MainActor in self.toolsUpdateState = .running(fraction) }
                }
                toolsUpdateState = .succeeded(result.version)
                refreshInstalledYtDlpVersion()
            } catch {
                toolsUpdateState = .failed(Self.describe(error))
            }
        }
    }

    // MARK: - Foto delle etichette

    func setLabelImage(contentsOf url: URL, side: VinylSide, for track: Track) {
        guard let paths else { return }
        applyLabelImage(side: side, for: track) {
            try ArtworkStore.save(contentsOf: url, trackID: track.id, side: side, paths: paths)
        }
    }

    func setLabelImageFromPasteboard(side: VinylSide, for track: Track) {
        guard let paths else { return }
        guard let image = ArtworkStore.imageFromPasteboard() else {
            transientError = "Negli appunti non c'è un'immagine."
            return
        }
        applyLabelImage(side: side, for: track) {
            try ArtworkStore.save(image: image, trackID: track.id, side: side, paths: paths)
        }
    }

    func removeLabelImage(side: VinylSide, for track: Track) {
        guard let paths else { return }
        let existing = side == .a ? track.labelImageAFilename : track.labelImageBFilename
        if let existing { ArtworkStore.remove(filename: existing, paths: paths) }

        var updated = track
        switch side {
        case .a: updated.labelImageAFilename = nil
        case .b: updated.labelImageBFilename = nil
        }
        save(track: updated)
    }

    private func applyLabelImage(
        side: VinylSide,
        for track: Track,
        write: () throws -> String
    ) {
        do {
            let filename = try write()
            var updated = track
            switch side {
            case .a: updated.labelImageAFilename = filename
            case .b: updated.labelImageBFilename = filename
            }
            save(track: updated)
        } catch {
            transientError = Self.describe(error)
        }
    }

    // MARK: - Scalette

    func createPlaylist() {
        guard let playlists else { return }
        Task {
            do {
                let playlist = try await playlists.createPlaylist(name: "Nuova scaletta")
                selection = .playlist(playlist.id)
            } catch {
                transientError = "Creazione non riuscita: \(error.localizedDescription)"
            }
        }
    }

    func deletePlaylist(id: String) {
        guard let playlists else { return }
        Task {
            try? await playlists.deletePlaylist(id: id)
            if selection == .playlist(id) { selection = .library }
        }
    }

    // MARK: - Righe di scaletta

    /// Accoda dei brani in fondo alla scaletta, nell'ordine dato.
    func appendTracks(_ trackIDs: [String], to playlistID: String) {
        guard let playlists, !trackIDs.isEmpty else { return }
        Task {
            do {
                for trackID in trackIDs {
                    try await playlists.appendTrack(trackID, to: playlistID)
                }
            } catch {
                transientError = "Non ho potuto aggiungere il brano: \(error.localizedDescription)"
            }
        }
    }

    /// Inserisce dei brani a una certa altezza della scaletta, facendo scorrere il resto.
    func insertTracks(_ trackIDs: [String], into playlistID: String, at index: Int) {
        guard let playlists, !trackIDs.isEmpty else { return }
        Task {
            do {
                for (offset, trackID) in trackIDs.enumerated() {
                    try await playlists.insertTrack(trackID, into: playlistID, at: index + offset)
                }
            } catch {
                transientError = "Non ho potuto inserire il brano: \(error.localizedDescription)"
            }
        }
    }

    /// Aggiunge una riga di nota. `index` a `nil` la mette in fondo.
    func addNote(to playlistID: String, at index: Int? = nil) {
        guard let playlists else { return }
        Task {
            do {
                try await playlists.insertNote(into: playlistID, at: index)
            } catch {
                transientError = "Non ho potuto aggiungere la nota: \(error.localizedDescription)"
            }
        }
    }

    func save(item: PlaylistItem) {
        guard let playlists else { return }
        Task {
            do { try await playlists.save(item) }
            catch { transientError = "Salvataggio non riuscito: \(error.localizedDescription)" }
        }
    }

    func deleteItems(ids: Set<String>, in playlistID: String) {
        guard let playlists, !ids.isEmpty else { return }
        Task {
            do {
                for id in ids {
                    try await playlists.deleteItem(id: id, in: playlistID)
                }
            } catch {
                transientError = "Non ho potuto eliminare la riga: \(error.localizedDescription)"
            }
        }
    }

    func reorderPlaylist(_ playlistID: String, orderedIDs: [String]) {
        guard let playlists else { return }
        Task {
            do { try await playlists.reorder(playlistID: playlistID, orderedItemIDs: orderedIDs) }
            catch { transientError = "Riordino non riuscito: \(error.localizedDescription)" }
        }
    }

    /// Carica sul deck la traccia con questo identificativo, se esiste ancora in libreria.
    func loadTrack(id: String, on slot: DeckState.Slot) {
        guard let track = trackList.first(where: { $0.id == id }) else { return }
        load(track, on: slot)
    }

    func rename(playlist: Playlist, to name: String) {
        guard let playlists else { return }
        var updated = playlist
        updated.name = name
        Task { try? await playlists.save(updated) }
    }
}
