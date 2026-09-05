import AVFoundation
import Foundation

/// Un deck: la traccia in RAM, la testina, il varispeed e il nodo che li mette in suono.
///
/// La posizione è **nostra**, non del framework: il playhead è un frame frazionario che avanza
/// dentro il render callback, quindi ciò che `positionSeconds` riporta è esattamente il sample
/// che sta uscendo dal device. È il motivo per cui il deck è costruito su `AVAudioSourceNode` e
/// non su `AVAudioPlayerNode`, che riporta la posizione del suo buffer interno e in pausa non la
/// riporta affatto.
@MainActor
public final class DeckEngine {
    /// Corsa del fader di pitch, in percento. Otto per lato come un SL-1200: è il riferimento
    /// per cui l'app esiste, e un range più largo darebbe un'idea sbagliata di quanto si potrà
    /// tirare il pezzo sul piatto vero.
    public static let pitchRangePercent = 8.0

    /// Entro quanto la testina si considera "sul cue". Serve perché il confronto è fra due
    /// `Double` che passano da un'andata e ritorno in frame: cinque millisecondi sono inudibili,
    /// e se uno scrub finisce così vicino al cue è comunque quel punto che si voleva.
    public static let cueTolerance = 0.005

    /// Scostamento massimo del *pitch bend*, cioè della spinta momentanea: ±3%, come quanto si
    /// riesce a spingere un piatto col dito senza far sentire che è stato spinto.
    public static let bendRangePercent = 3.0

    /// Di quanto sposta la testina un colpo di nudge: dieci millisecondi, che si sentono come uno
    /// scarto di fase e non come un salto.
    ///
    /// **Resta un tempo assoluto anche adesso che c'è la beatgrid**, e non una frazione di
    /// battuta: il nudge serve a mettere in fase due dischi, cioè a recuperare uno scarto di
    /// millisecondi che non ha niente a che vedere con il tempo del pezzo. Legarlo alla griglia lo
    /// renderebbe anche più grosso sui pezzi lenti, che è l'opposto di quello che serve, e
    /// smetterebbe di funzionare sulle tracce senza griglia.
    public static let nudgeSeconds = 0.01

    /// I nodi li collega `AudioGraph`: il deck non sa in che grafo è finito.
    let sourceNode: AVAudioSourceNode
    let mixerNode: AVAudioMixerNode
    weak var graph: AudioGraph?

    private let state: DeckRenderState
    /// Frequenza del grafo, fissa per tutta la vita del nodo: la conversione verso il device la
    /// fa il mixer, quindi cambiare device non sposta il pitch.
    private let graphSampleRate: Double

    /// Il riferimento forte alla traccia in suono. Il thread audio legge solo puntatori: tenerla
    /// viva — e liberarla al momento giusto — è compito del main.
    private var loaded: DecodedTrack?
    /// Il descrittore pubblicato, tenuto come bit del puntatore e non come puntatore tipizzato:
    /// il `deinit` di una classe sul main actor può leggere solo proprietà `Sendable`.
    private var descriptorBits: UInt = 0

    /// Ultimo errore di avvio del grafo, da mostrare invece di un pulsante che non fa niente.
    public private(set) var lastError: String?

    /// Il cue di lavoro, quello del tasto CUE. Vive in RAM e non in tabella: i punti annotati —
    /// hot cue e memory cue — sono un'altra cosa e hanno la loro riga nel database.
    public private(set) var cueSeconds: Double = 0
    /// Sta suonando solo perché il tasto CUE è tenuto premuto.
    public private(set) var isPreviewingCue = false

    /// Griglia a cui agganciare i cue. `nil` quando il quantize è spento o la traccia non ha una
    /// griglia: in entrambi i casi il punto si prende dov'è la testina.
    ///
    /// Il quantize vive **qui** e non nella vista perché è il motore a possedere il cue di
    /// lavoro: se lo spostamento del cue si agganciasse solo nell'interfaccia, il tasto CUE
    /// premuto da tastiera aggirerebbe la griglia senza che si veda perché.
    public var quantizeGrid: Beatgrid?
    public var quantizeResolution: QuantizeResolution = .beat

    private var storedPitch: Double = 0
    private var storedBend: Double = 0
    private var storedGain: Double = 1
    /// Quota assegnata dal crossfader, moltiplicata al gain del deck.
    private var crossfaderGain: Double = 1

    init(format: AVAudioFormat) {
        let state = DeckRenderState()
        self.state = state
        graphSampleRate = format.sampleRate
        mixerNode = AVAudioMixerNode()
        sourceNode = AVAudioSourceNode(
            format: format,
            renderBlock: Self.makeRenderBlock(state: state)
        )
    }

    /// Il render block va costruito **fuori dal main actor e marcato `@Sendable`**, e questo è
    /// tutt'altro che un dettaglio di stile.
    ///
    /// `AVAudioSourceNodeRenderBlock` è un blocco Objective-C importato senza `@Sendable`: una
    /// closure creata dentro l'`init` di questa classe — che è `@MainActor` — ne **eredita
    /// implicitamente l'isolamento**, e il compilatore le mette in testa un controllo di
    /// esecutore. Il thread audio non è la coda principale, quindi al primo buffer
    /// `dispatch_assert_queue` fa `SIGTRAP` e l'app muore appena si premono play. Costruirlo in
    /// un metodo `nonisolated` e dichiarare la closure `@Sendable` toglie sia l'ereditarietà sia
    /// il controllo.
    nonisolated private static func makeRenderBlock(
        state: DeckRenderState
    ) -> AVAudioSourceNodeRenderBlock {
        { @Sendable isSilence, _, frameCount, bufferList in
            state.render(
                frameCount: Int(frameCount),
                into: bufferList,
                isSilence: isSilence
            )
        }
    }

    deinit {
        Self.free(descriptorBits)
    }

    // MARK: - Traccia

    public var hasTrack: Bool { loaded != nil }

    public var durationSeconds: Double { loaded?.durationSeconds ?? 0 }

    /// Mette una traccia decodificata sul deck, con la testina all'inizio.
    ///
    /// Il `DecodedAudio` che arriva si può rilasciare subito dopo: qui viene copiato nella forma
    /// che il thread audio sa leggere.
    public func load(_ audio: DecodedAudio) {
        state.setPlaying(false)
        isPreviewingCue = false
        cueSeconds = 0
        // Il fader di pitch è un comando fisico e resta dove l'ha messo l'utente; la spinta
        // momentanea no, non ha senso ereditarla dalla traccia precedente.
        storedBend = 0
        applyRate()
        let track = DecodedTrack(audio: audio)

        let reference = UnsafeMutablePointer<DeckTrackRef>.allocate(capacity: 1)
        reference.initialize(
            to: DeckTrackRef(
                left: track.base(ofChannel: 0),
                right: track.channelCount > 1 ? track.base(ofChannel: 1) : nil,
                frameCount: track.frameCount,
                baseStep: baseStep(forFileRate: track.sampleRate),
                sampleRate: track.sampleRate
            )
        )
        state.setSampleRate(track.sampleRate)
        publish(UInt(bitPattern: UnsafeMutableRawPointer(reference)), keeping: track)
        state.requestSeek(toFrame: 0)
    }

    public func unload() {
        state.setPlaying(false)
        state.setSampleRate(0)
        isPreviewingCue = false
        cueSeconds = 0
        quantizeGrid = nil
        publish(0, keeping: nil)
    }

    /// Aggancia un istante alla griglia, se il quantize è attivo, e lo tiene dentro la traccia.
    ///
    /// Non lo chiamano seek e scrub: quelli devono andare esattamente dove va il dito, altrimenti
    /// trascinando la waveform la testina salterebbe di battuta in battuta. Il quantize riguarda
    /// i **punti che si memorizzano e si richiamano**, non il movimento.
    public func quantized(_ seconds: Double) -> Double {
        guard let quantizeGrid, durationSeconds > 0 else { return seconds }
        let snapped = quantizeGrid.snap(seconds, resolution: quantizeResolution)
        return min(max(0, snapped), durationSeconds)
    }

    private func baseStep(forFileRate fileRate: Double) -> Double {
        guard fileRate > 0, graphSampleRate > 0 else { return 1 }
        return fileRate / graphSampleRate
    }

    // MARK: - Trasporto

    public var isPlaying: Bool { state.isPlaying }

    /// Il thread audio si è fermato da sé perché la traccia è finita.
    public var hasReachedEnd: Bool { state.hasReachedEnd }

    /// In fondo alla traccia `play` non fa niente, come un piatto arrivato al centro del disco:
    /// far ripartire da capo un pezzo finito, in mezzo a un set, sarebbe peggio di un pulsante
    /// che non risponde. Basta riportare indietro la testina.
    public func play() {
        // Un comando di trasporto esplicito chiude l'anteprima: da qui in poi il CUE non deve
        // riportare indietro la testina al rilascio.
        isPreviewingCue = false
        guard loaded != nil, !state.hasReachedEnd else { return }
        do {
            try graph?.startIfNeeded()
        } catch {
            lastError = "Il device audio non è disponibile: \(error.localizedDescription)"
            return
        }
        lastError = nil
        state.setPlaying(true)
    }

    public func pause() {
        isPreviewingCue = false
        state.setPlaying(false)
    }

    public func togglePlay() {
        if isPlaying { pause() } else { play() }
    }

    /// Dove si trova la testina, in secondi di traccia.
    ///
    /// `nonisolated` di proposito: la legge il renderer Metal 60 volte al secondo, e passare dal
    /// main actor per due letture atomiche non avrebbe senso.
    public nonisolated var positionSeconds: Double { state.positionSeconds }

    public func seek(toSeconds seconds: Double) {
        guard let loaded, loaded.sampleRate > 0 else { return }
        let clamped = min(max(0, seconds), loaded.durationSeconds)
        state.requestSeek(toFrame: clamped * loaded.sampleRate)
    }

    // MARK: - Tasto CUE

    /// I tre comportamenti del tasto CUE di un CDJ, che sono tre perché il tasto legge lo stato
    /// del deck e non fa una cosa sola:
    ///
    /// - **in play** → torna al cue e si ferma lì (*back cue*);
    /// - **in pausa sul cue** → suona finché il tasto resta premuto, e al rilascio torna indietro;
    /// - **in pausa altrove** → il cue si sposta nella posizione corrente, agganciato alla
    ///   griglia se il quantize è attivo.
    ///
    /// Il terzo caso è quello che sorprende chi non ci è abituato — mettere in pausa a metà pezzo
    /// e premere CUE *sposta* il cue — ma è il comportamento del CDJ, ed è quello per cui l'app
    /// esiste: quello che si impara qui deve valere davanti al piatto.
    ///
    /// Arrivati in fondo alla traccia il tasto fa *back cue* come in play: il deck si è fermato da
    /// sé, non lo ha fermato l'utente, e piazzare il cue sull'ultimo frame non servirebbe a nulla.
    public func pressCue() {
        guard loaded != nil else { return }

        if isPlaying || state.hasReachedEnd {
            pause()
            seek(toSeconds: cueSeconds)
            return
        }

        if isAtCue {
            play()
            isPreviewingCue = isPlaying
        } else {
            cueSeconds = quantized(min(max(0, positionSeconds), durationSeconds))
        }
    }

    /// Fine dell'anteprima: si torna al cue e si resta fermi. Se il tasto non aveva avviato
    /// nessuna anteprima non fa niente, così un rilascio non può fermare una riproduzione
    /// avviata dal play.
    public func releaseCue() {
        guard isPreviewingCue else { return }
        pause()
        seek(toSeconds: cueSeconds)
    }

    public var isAtCue: Bool {
        abs(positionSeconds - cueSeconds) < Self.cueTolerance
    }

    // MARK: - Pitch e livelli

    /// Varispeed: velocità e tonalità legate, come su un giradischi. Niente keylock, per scelta.
    public var pitchPercent: Double {
        get { storedPitch }
        set {
            let range = Self.pitchRangePercent
            storedPitch = min(max(-range, newValue), range)
            applyRate()
        }
    }

    /// La spinta momentanea, che si somma al fader senza spostarlo.
    ///
    /// È il modo pulito di mettere una traccia in fase con quella sull'altro deck: accelerare per
    /// un attimo sposta la fase senza schiocchi, mentre un salto della testina si sente. Al
    /// rilascio si torna al valore del fader, che non è stato toccato.
    public var bendPercent: Double { storedBend }

    public func setBend(_ percent: Double) {
        let range = Self.bendRangePercent
        storedBend = min(max(-range, percent), range)
        applyRate()
    }

    public func clearBend() {
        setBend(0)
    }

    /// Rapporto di velocità effettivo: 1,04 con il fader a +4%, spinta compresa.
    public var rate: Double { 1 + (storedPitch + storedBend) / 100 }

    private func applyRate() {
        state.setRate(rate)
    }

    /// Sposta la testina di un soffio, avanti o indietro.
    public func nudge(bySeconds delta: Double) {
        guard loaded != nil else { return }
        seek(toSeconds: positionSeconds + delta)
    }

    public var gain: Double {
        get { storedGain }
        set {
            storedGain = min(max(0, newValue), 1)
            applyVolume()
        }
    }

    func setCrossfaderGain(_ value: Double) {
        crossfaderGain = min(max(0, value), 1)
        applyVolume()
    }

    private func applyVolume() {
        // Trascinando un fader arrivano molti valori identici di fila: scrivere `outputVolume`
        // significa toccare un parametro dell'audio unit mentre il motore gira, e non è gratis.
        let volume = Float(storedGain * crossfaderGain)
        guard volume != mixerNode.outputVolume else { return }
        mixerNode.outputVolume = volume
    }

    // MARK: - Pubblicazione e rilascio differito

    private func publish(_ bits: UInt, keeping track: DecodedTrack?) {
        let previousBits = descriptorBits
        let previousTrack = loaded
        descriptorBits = bits
        loaded = track
        _ = state.exchangeTrackRef(bits)

        if previousBits != 0 || previousTrack != nil {
            retire(bits: previousBits, track: previousTrack)
        }
    }

    /// Il thread audio può avere ancora in mano il descrittore vecchio: si attende che completi
    /// un render dopo lo scambio — da quel momento ha già riletto il puntatore nuovo — e solo
    /// allora si libera la memoria, **dal main thread**. Il tetto di 200 ms copre il caso del
    /// grafo fermo, in cui il contatore non avanzerà mai perché nessuno sta leggendo.
    private func retire(bits: UInt, track: DecodedTrack?) {
        let tickAtSwap = state.tick
        let state = self.state
        Task { @MainActor in
            for _ in 0..<40 {
                if state.tick != tickAtSwap { break }
                try? await Task.sleep(for: .milliseconds(5))
            }
            Self.free(bits)
            // Qui cadono i ~130 MB della traccia precedente, sul main thread e non dentro il
            // callback audio.
            withExtendedLifetime(track) {}
        }
    }

    nonisolated private static func free(_ bits: UInt) {
        guard let pointer = UnsafeMutablePointer<DeckTrackRef>(bitPattern: bits) else { return }
        pointer.deinitialize(count: 1)
        pointer.deallocate()
    }
}
