import DJKit
import Observation
import SwiftUI

/// Cosa c'è su un deck, dove si trova la testina e se sta suonando.
///
/// È il ponte fra la UI e `DeckEngine`: la vista osserva questa classe, il motore vive fuori dal
/// grafo di `@Observable` perché la sua posizione cambia a ogni buffer audio e non a ogni evento
/// di interfaccia.
///
/// **Due frequenze diverse per la stessa posizione.** `playheadSeconds` si aggiorna 20 volte al
/// secondo, ed è quella che alimenta timecode e overview: sono un testo e una riga su tutta la
/// traccia, dove un ventesimo di secondo non si vede. La waveform zoomata invece scorre a 60 fps
/// e legge la posizione **direttamente dal motore** tramite `livePositionProvider`, senza passare
/// da `@Observable`: ricostruire l'albero SwiftUI sessanta volte al secondo per far scorrere una
/// texture sarebbe lavoro buttato.
@MainActor
@Observable
final class DeckState: Identifiable {
    enum Slot: String, CaseIterable, Sendable {
        case a = "A"
        case b = "B"
    }

    nonisolated let slot: Slot
    nonisolated var id: String { slot.rawValue }

    private(set) var track: Track?
    private(set) var peaks: Peaks?
    private(set) var isLoading = false
    private(set) var loadError: String?
    /// Perché il deck non può suonare: audio mancante, illeggibile, o device non disponibile.
    private(set) var playbackError: String?
    private(set) var isPlaying = false
    /// Copia osservabile del cue di lavoro: la fonte è `DeckEngine`, qui serve perché le viste
    /// possano disegnarne il marker.
    private(set) var cueSeconds: Double = 0
    /// Tutti i cue point della traccia caricata, in ordine di posizione: hot cue e memory cue
    /// nella stessa lista, come stanno nel database.
    private(set) var cuePoints: [CuePoint] = []

    var playheadSeconds: Double = 0
    /// Quanti secondi di brano stanno nella vista zoomata. Otto secondi sono circa sedici battute
    /// a 128 BPM: abbastanza per vedere arrivare un cambio, abbastanza stretto per puntare un cue.
    var visibleSeconds: Double = 8

    /// Copie osservabili di ciò che vive nel motore. `DeckEngine` sta fuori da `@Observable`:
    /// senza queste, muovere un fader non farebbe ridisegnare niente — è lo stesso motivo per cui
    /// esiste `isAudioReady`.
    private var storedPitchPercent: Double = 0
    private var storedGain: Double = 1
    private(set) var isBending = false

    private var engine: DeckEngine?
    private var paths: LibraryPaths?
    private var repository: TrackRepository?
    private var ticker: Task<Void, Never>?

    /// Come segnalare all'app un errore che non riguarda la riproduzione — una scrittura di cue
    /// point che non è andata. Lo imposta `AppModel`, che lo mostra nell'avviso condiviso.
    var reportError: ((String) -> Void)?

    init(slot: Slot) {
        self.slot = slot
    }

    /// Libreria e database. Separato da `attach(engine:)` di proposito: se l'uscita audio non si
    /// configura il deck resta muto, ma waveform e cue point devono continuare a funzionare.
    func configure(paths: LibraryPaths, repository: TrackRepository) {
        self.paths = paths
        self.repository = repository
    }

    /// Collega il deck al suo nodo nel grafo audio.
    func attach(engine: DeckEngine) {
        self.engine = engine
    }

    var durationSeconds: Double {
        if let peaks, peaks.durationSeconds > 0 { return peaks.durationSeconds }
        return track?.durationSeconds ?? 0
    }

    var hasWaveform: Bool { peaks != nil }

    /// Gli hot cue per slot da 1 a 8. Derivato, non memorizzato: la fonte è `cuePoints`, e
    /// l'indice unico su `(trackID, hotcueSlot)` garantisce che ce ne sia al massimo uno per slot.
    var hotCues: [Int: CuePoint] {
        Dictionary(
            cuePoints.compactMap { cue in cue.hotcueSlot.map { ($0, cue) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    /// Cosa segnare sulle waveform.
    ///
    /// Il cue di lavoro va **per ultimo**: nel fragment shader i marker si disegnano nell'ordine
    /// in cui arrivano, quindi l'ultimo vince dove due cadono nello stesso pixel, e fra tutti è
    /// lui quello che si sposta e che serve vedere.
    var cueMarkers: [CueMarker] {
        var markers = cuePoints.map(CueMarker.init(cuePoint:))
        if isAudioReady {
            markers.append(.working(atSeconds: cueSeconds))
        }
        return markers
    }

    /// L'audio è in RAM e il motore è pronto a suonare.
    ///
    /// È una **copia osservabile** di `DeckEngine.hasTrack`, e la distinzione non è teorica:
    /// `DeckEngine` vive fuori da `@Observable`, quindi finire la decodifica non cambia niente
    /// che SwiftUI stia osservando. Leggendo il motore direttamente, il tasto play restava
    /// disabilitato fino al primo tocco di qualcos'altro — segnalato da Gabriel il 2026-09-04.
    /// Ogni stato del motore che serve a una vista va ricopiato qui.
    private(set) var isAudioReady = false

    var canPlay: Bool { isAudioReady }

    /// La testina è sul cue, quindi il prossimo colpo di CUE è un'anteprima e non uno
    /// spostamento. Il confronto usa `playheadSeconds` — la copia osservabile — perché è ciò che
    /// fa riaccendere la spia del tasto quando la testina ci torna sopra.
    var isAtCue: Bool {
        canPlay && abs(playheadSeconds - cueSeconds) < DeckEngine.cueTolerance
    }

    /// Sonda della posizione per il renderer Metal: leggibile da qualsiasi thread, costa due
    /// letture atomiche. `nil` quando non c'è audio caricato, così la waveform continua a seguire
    /// il trascinamento anche se la traccia non si è potuta decodificare.
    /// La posizione in questo istante, non quella dell'ultimo aggiornamento a 20 Hz: è quella su
    /// cui va piazzato un cue, altrimenti il punto cade fino a 50 ms più indietro di dov'era la
    /// testina quando si è premuto.
    var exactPlayheadSeconds: Double {
        guard isAudioReady, let engine else { return playheadSeconds }
        return engine.positionSeconds
    }

    var livePositionProvider: (@Sendable () -> Double)? {
        guard isAudioReady, let engine else { return nil }
        return { engine.positionSeconds }
    }

    // MARK: - Caricamento

    func load(track: Track, analyzer: TrackAnalyzer?) async {
        stopTicker()
        engine?.unload()
        self.track = track
        peaks = nil
        playheadSeconds = 0
        loadError = nil
        playbackError = nil
        isPlaying = false
        cueSeconds = 0
        isAudioReady = false
        cuePoints = []
        isBending = false

        isLoading = true
        defer { isLoading = false }

        // I cue point per primi: sono una lettura da SQLite, quindi i pad si accendono subito
        // mentre waveform e audio arrivano dopo.
        await loadCues(trackID: track.id)

        // Prima la waveform: si vede subito, ed è quella che serve per decidere dove attaccare.
        if let analyzer {
            do {
                peaks = try await analyzer.loadPeaks(for: track)
                if peaks == nil { loadError = "Waveform non ancora calcolata." }
            } catch {
                loadError = Self.describe(error)
            }
        }

        await loadAudio(track: track)
    }

    /// Decodifica la traccia intera in RAM e la passa al motore.
    ///
    /// Fuori dal main actor: sono un paio di centinaia di MB e circa 0,3 s di CPU per un brano di
    /// sei minuti — sul main si vedrebbe come una finestra che si blocca.
    private func loadAudio(track: Track) async {
        guard let engine else { return }
        guard let filename = track.audioFilename, let paths else {
            playbackError = "Nessun file audio: la traccia va riscaricata."
            return
        }

        let url = paths.audioURL(filename: filename)
        do {
            let audio = try await Task.detached(priority: .userInitiated) {
                try AudioDecoder.decode(url: url)
            }.value
            // Nel frattempo l'utente può aver caricato un'altra traccia su questo deck.
            guard self.track?.id == track.id else { return }
            engine.load(audio)
            cueSeconds = engine.cueSeconds
            isAudioReady = true
        } catch {
            playbackError = Self.describe(error)
        }
    }

    /// Ricarica la cache dopo un ricalcolo, tenendo ferma la posizione.
    func reloadPeaks(track: Track, analyzer: TrackAnalyzer?) async {
        guard self.track?.id == track.id, let analyzer else { return }
        self.track = track
        loadError = nil
        peaks = try? await analyzer.loadPeaks(for: track)
    }

    func clear() {
        stopTicker()
        engine?.unload()
        track = nil
        peaks = nil
        playheadSeconds = 0
        loadError = nil
        playbackError = nil
        isPlaying = false
        cueSeconds = 0
        isAudioReady = false
        cuePoints = []
        isBending = false
    }

    // MARK: - Trasporto

    func togglePlay() {
        guard let engine, engine.hasTrack else { return }
        engine.togglePlay()
        syncAfterTransport()
    }

    /// I tre comportamenti del tasto stanno in `DeckEngine.pressCue`: qui si ricopia solo ciò che
    /// il motore ha deciso.
    func pressCue() {
        guard let engine, engine.hasTrack else { return }
        engine.pressCue()
        syncAfterTransport()
    }

    func releaseCue() {
        guard let engine, engine.hasTrack else { return }
        engine.releaseCue()
        syncAfterTransport()
    }

    // MARK: - Pitch, gain, nudge

    /// Posizione del fader di pitch, in percento. Il varispeed lega velocità e tonalità: alzando
    /// il pitch sale anche la nota, come sul piatto.
    var pitchPercent: Double {
        get { storedPitchPercent }
        set {
            let range = DeckEngine.pitchRangePercent
            storedPitchPercent = min(max(-range, newValue), range)
            engine?.pitchPercent = storedPitchPercent
        }
    }

    var gain: Double {
        get { storedGain }
        set {
            storedGain = min(max(0, newValue), 1)
            engine?.gain = storedGain
        }
    }

    /// Il BPM che si sentirebbe adesso, cioè quello della traccia corretto dal fader. `nil`
    /// finché l'analisi del tempo non c'è (arriva in M6).
    ///
    /// La spinta momentanea **non** entra nel conto: farebbe ballare il numero proprio mentre si
    /// sta cercando di leggerlo, e quello che serve sapere è dove si è messo il fader.
    var effectiveBPM: Double? {
        guard let bpm = track?.bpm, bpm > 0 else { return nil }
        return bpm * (1 + storedPitchPercent / 100)
    }

    /// Un colpetto: sposta la testina di un passo esatto.
    func nudge(forward: Bool) {
        guard let engine, engine.hasTrack else { return }
        engine.nudge(bySeconds: forward ? DeckEngine.nudgeSeconds : -DeckEngine.nudgeSeconds)
        playheadSeconds = engine.positionSeconds
    }

    /// Spinta tenuta: accelera o rallenta finché il tasto resta premuto, senza toccare il fader.
    func startBend(forward: Bool) {
        guard let engine, engine.hasTrack else { return }
        engine.setBend(forward ? DeckEngine.bendRangePercent : -DeckEngine.bendRangePercent)
        isBending = true
    }

    func endBend() {
        engine?.clearBend()
        isBending = false
    }

    // MARK: - Hot cue

    /// Il pad di uno slot.
    ///
    /// **Pad pieno**: porta la testina lì e fa suonare, sia che il deck stesse suonando sia che
    /// fosse in pausa — è il comportamento del CDJ, dove il pad serve ad ascoltare quel punto.
    /// Diverso dal tasto CUE, che in pausa sul cue suona solo finché lo si tiene premuto.
    ///
    /// **Pad vuoto**: memorizza il punto in cui si è adesso, col colore dello slot.
    func pressHotCue(slot: Int) {
        guard track != nil else { return }

        if let cue = hotCues[slot] {
            seek(toSeconds: cue.positionSeconds)
            engine?.play()
            syncAfterTransport()
        } else {
            setHotCue(slot: slot, atSeconds: exactPlayheadSeconds)
        }
    }

    func deleteHotCue(slot: Int) {
        guard let repository, let cue = hotCues[slot] else { return }
        remove(cueID: cue.id)
        Task {
            do {
                try await repository.deleteCuePoint(id: cue.id)
            } catch {
                reportError?("Non ho potuto cancellare l'hot cue: \(Self.describe(error))")
                await loadCues(trackID: cue.trackID)
            }
        }
    }

    /// Salva nome e nota di un hot cue già esistente.
    func update(cue: CuePoint) {
        guard let repository else { return }
        upsert(cue)
        Task {
            do {
                try await repository.save(cue)
            } catch {
                reportError?("Non ho potuto salvare la nota: \(Self.describe(error))")
                await loadCues(trackID: cue.trackID)
            }
        }
    }

    private func setHotCue(slot: Int, atSeconds seconds: Double) {
        guard let repository, let track else { return }
        let cue = CuePoint(
            trackID: track.id,
            positionSeconds: min(max(0, seconds), max(0, durationSeconds)),
            colorIndex: slot - 1,
            hotcueSlot: slot
        )
        // Aggiornamento ottimistico: il pad si accende sotto il dito, la scrittura segue.
        upsert(cue)
        Task {
            do {
                try await repository.assignHotCue(cue, toSlot: slot)
            } catch {
                reportError?("Non ho potuto salvare l'hot cue: \(Self.describe(error))")
                await loadCues(trackID: track.id)
            }
        }
    }

    /// Rilegge i cue point dal database. Serve al caricamento e a rimettere in pari lo stato
    /// dopo una scrittura fallita.
    ///
    /// Non c'è `ValueObservation` qui, a differenza delle liste di `AppModel`: il deck è l'unico
    /// che scrive i propri cue. L'unico caso che resta scoperto è la stessa traccia caricata sui
    /// due deck, dove i pad dell'altro restano indietro fino al ricaricamento — e servirà
    /// un'osservazione quando l'ispettore permetterà di modificare i cue da fuori.
    private func loadCues(trackID: String) async {
        guard let repository else { return }
        do {
            let cues = try await repository.cuePoints(trackID: trackID)
            guard track?.id == trackID else { return }
            cuePoints = cues
        } catch {
            reportError?("Non ho potuto leggere i cue point: \(Self.describe(error))")
        }
    }

    /// Inserisce o sostituisce un cue point, tenendo la lista in ordine di posizione.
    ///
    /// Se il cue occupa uno slot già preso, il vecchio occupante **diventa un memory cue** invece
    /// di sparire: è quello che fa `TrackRepository.assignHotCue` nel database, e le due copie
    /// devono raccontare la stessa cosa.
    private func upsert(_ cue: CuePoint) {
        if let slot = cue.hotcueSlot {
            for index in cuePoints.indices
            where cuePoints[index].hotcueSlot == slot && cuePoints[index].id != cue.id {
                cuePoints[index].hotcueSlot = nil
            }
        }
        if let index = cuePoints.firstIndex(where: { $0.id == cue.id }) {
            cuePoints[index] = cue
        } else {
            cuePoints.append(cue)
        }
        cuePoints.sort { $0.positionSeconds < $1.positionSeconds }
    }

    private func remove(cueID: String) {
        cuePoints.removeAll { $0.id == cueID }
    }

    // MARK: - Posizione

    func seek(toSeconds seconds: Double) {
        let clamped = min(max(0, seconds), max(0, durationSeconds))
        playheadSeconds = clamped
        engine?.seek(toSeconds: clamped)
    }

    func zoom(byFactor factor: Double) {
        visibleSeconds = min(64, max(1, visibleSeconds / factor))
    }

    // MARK: - Sincronizzazione con il motore

    /// Ricopia la posizione dal motore 20 volte al secondo mentre suona, e si spegne da sé
    /// quando il thread audio si ferma — cosa che decide lui, alla fine della traccia.
    private func startTicker() {
        guard ticker == nil else { return }
        ticker = Task { @MainActor [weak self] in
            while let self, self.isPlaying {
                self.syncFromEngine()
                try? await Task.sleep(for: .milliseconds(50))
            }
            self?.ticker = nil
        }
    }

    private func stopTicker() {
        ticker?.cancel()
        ticker = nil
    }

    /// Riallinea lo stato osservabile dopo un comando di trasporto. Serve perché il motore vive
    /// fuori da `@Observable`: se qualcosa non si aggiorna nella fascia del deck, è quasi sempre
    /// una chiamata al motore senza questa riga dietro.
    private func syncAfterTransport() {
        // Senza audio caricato `positionSeconds` vale 0: ricopiarlo cancellerebbe la posizione
        // raggiunta trascinando la waveform di una traccia con i soli peaks.
        guard let engine, engine.hasTrack else { return }
        isPlaying = engine.isPlaying
        playheadSeconds = engine.positionSeconds
        cueSeconds = engine.cueSeconds
        isAudioReady = engine.hasTrack
        playbackError = engine.lastError
        if isPlaying { startTicker() }
    }

    private func syncFromEngine() {
        guard let engine else { return }
        playheadSeconds = engine.positionSeconds
        if !engine.isPlaying { isPlaying = false }
    }

    private static func describe(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
