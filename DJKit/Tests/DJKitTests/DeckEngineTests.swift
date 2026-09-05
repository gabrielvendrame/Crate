import AVFoundation
import Testing
@testable import DJKit

/// Il deck dentro un vero `AVAudioEngine`, in **modalità di rendering manuale**: la catena di
/// nodi è quella dell'app, ma i buffer li chiediamo noi e non serve nessun device audio.
///
/// È l'unico modo di verificare con `swift test` che dal `AVAudioSourceNode` esca davvero
/// qualcosa — cioè che il grafo sia collegato e il formato coincida. L'alternativa era scoprirlo
/// a orecchio.
/// Passa un oggetto non-`Sendable` a un altro thread. Serve al test che pilota il rendering da
/// un `Task.detached`: `renderOffline` è fatto per essere chiamato da un thread di lavoro, ma
/// `AVAudioEngine` non è `Sendable` e il compilatore non ha modo di saperlo.
private struct UnsafeHandoff<Value>: @unchecked Sendable {
    let value: Value
}

@MainActor
@Suite("Deck dentro il grafo audio")
struct DeckEngineTests {
    private static let sampleRate = 44_100.0

    private func format() -> AVAudioFormat {
        AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2)!
    }

    /// Segnale continuo invece di una rampa: attraversando mixer e conversioni resta identico a
    /// se stesso, quindi un valore diverso da quello atteso è un problema del grafo e non
    /// dell'interpolazione.
    private func constant(_ value: Float, frames: Int) -> DecodedAudio {
        DecodedAudio(
            channels: [
                [Float](repeating: value, count: frames),
                [Float](repeating: value, count: frames),
            ],
            sampleRate: Self.sampleRate,
            frameCount: frames
        )
    }

    private func makeGraph(
        _ deck: DeckEngine,
        format: AVAudioFormat,
        maximumFrameCount: AVAudioFrameCount = 1024
    ) throws -> AVAudioEngine {
        let engine = AVAudioEngine()
        // **Il rendering manuale si abilita per primo**, prima di toccare `mainMixerNode`.
        // Collegando i nodi prima, l'engine istanzia l'uscita *hardware* per sapere che formato
        // ha, e da lì passa dal HAL: se in quel momento il device è occupato — l'app aperta, un
        // altro test che sta avviando il suo engine — `start()` fallisce con `-80802`
        // («manual rendering: not running») dopo un paio di secondi di attesa. Con questa riga in
        // testa l'uscita è il renderer manuale fin dall'inizio e l'hardware non c'entra più.
        try engine.enableManualRenderingMode(
            .offline, format: format, maximumFrameCount: maximumFrameCount
        )
        engine.attach(deck.sourceNode)
        engine.attach(deck.mixerNode)
        engine.connect(deck.sourceNode, to: deck.mixerNode, format: format)
        engine.connect(deck.mixerNode, to: engine.mainMixerNode, format: format)
        try engine.start()
        return engine
    }

    private func render(
        _ engine: AVAudioEngine,
        frames: AVAudioFrameCount
    ) throws -> AVAudioPCMBuffer {
        let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat, frameCapacity: frames
        )!
        let status = try engine.renderOffline(frames, to: buffer)
        #expect(status == .success)
        return buffer
    }

    @Test("Dal source node esce il segnale caricato")
    func producesAudio() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.5, frames: 4096))
        deck.play()
        #expect(deck.isPlaying)

        let buffer = try render(engine, frames: 512)
        let samples = buffer.floatChannelData![0]
        for index in 0..<512 {
            #expect(abs(samples[index] - 0.5) < 0.01)
        }
        #expect(abs(deck.positionSeconds - 512 / Self.sampleRate) < 1e-6)
    }

    @Test("In pausa il grafo gira e non esce niente")
    func pausedProducesSilence() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.5, frames: 4096))
        let buffer = try render(engine, frames: 256)
        let samples = buffer.floatChannelData![0]
        for index in 0..<256 {
            #expect(samples[index] == 0)
        }
        #expect(deck.positionSeconds == 0)
    }

    /// Il pitch non aggiunge nodi: consuma più traccia per lo stesso numero di frame in uscita.
    /// A +8% un secondo di uscita mangia 1,08 secondi di brano, ed è esattamente ciò che succede
    /// alzando il fader su un giradischi.
    @Test("Il fader di pitch consuma la traccia più in fretta")
    func pitchAdvancesFaster() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.3, frames: 44_100))
        deck.pitchPercent = 8
        #expect(abs(deck.rate - 1.08) < 1e-9)
        deck.play()

        _ = try render(engine, frames: 1024)
        #expect(abs(deck.positionSeconds - 1024 * 1.08 / Self.sampleRate) < 1e-6)
    }

    @Test("La corsa del fader è limitata a ±8%")
    func pitchIsClamped() {
        let deck = DeckEngine(format: format())
        deck.pitchPercent = 40
        #expect(deck.pitchPercent == 8)
        deck.pitchPercent = -40
        #expect(deck.pitchPercent == -8)
    }

    @Test("Il seek sposta la testina anche a deck fermo")
    func seekWhilePaused() {
        let deck = DeckEngine(format: format())
        deck.load(constant(0.2, frames: 44_100))
        deck.seek(toSeconds: 0.5)
        #expect(abs(deck.positionSeconds - 0.5) < 1e-6)

        deck.seek(toSeconds: 99)
        #expect(abs(deck.positionSeconds - 1) < 1e-6, "oltre la fine si ferma all'ultimo frame")
        deck.seek(toSeconds: -3)
        #expect(deck.positionSeconds == 0)
    }

    @Test("Arrivata in fondo, la traccia si ferma e play non la fa ripartire da capo")
    func stopsAtEndAndStaysThere() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.4, frames: 512))
        deck.play()
        _ = try render(engine, frames: 1024)

        #expect(deck.isPlaying == false)
        #expect(deck.hasReachedEnd)
        #expect(abs(deck.positionSeconds - 512 / Self.sampleRate) < 1e-6)

        deck.play()
        #expect(deck.isPlaying == false, "in fondo al disco il play non fa niente")

        deck.seek(toSeconds: 0)
        deck.play()
        #expect(deck.isPlaying, "riportata indietro la testina, riparte")
    }

    @Test("Cambiare traccia mentre suona scambia il buffer e riparte dall'inizio")
    func swapWhilePlaying() async throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.5, frames: 44_100))
        deck.play()
        _ = try render(engine, frames: 512)

        deck.load(constant(0.25, frames: 22_050))
        #expect(deck.isPlaying == false, "il caricamento ferma il deck")
        #expect(abs(deck.durationSeconds - 0.5) < 1e-6)
        #expect(deck.positionSeconds == 0)

        deck.play()
        let buffer = try render(engine, frames: 256)
        let samples = buffer.floatChannelData![0]
        for index in 0..<256 {
            #expect(abs(samples[index] - 0.25) < 0.01)
        }

        // Il tempo che il rilascio differito aspetta prima di liberare il buffer precedente: se
        // liberasse troppo presto, o due volte, il test cadrebbe qui.
        try await Task.sleep(for: .milliseconds(250))
        #expect(deck.hasTrack)
    }

    /// **Test di regressione su un crash vero.** Il render block di un `AVAudioSourceNode` è un
    /// blocco Objective-C importato senza `@Sendable`: costruito dentro un contesto `@MainActor`
    /// ne eredita l'isolamento, e il compilatore gli mette in testa un controllo di esecutore.
    /// Il thread audio non è la coda principale, quindi al primo buffer `dispatch_assert_queue`
    /// fa `SIGTRAP`: l'app moriva appena si premeva play, mentre tutti gli altri test passavano
    /// perché `renderOffline` chiamato dal main thread supera quel controllo.
    ///
    /// Qui il rendering parte da un `Task.detached`, cioè da un thread qualsiasi — la stessa
    /// condizione del thread audio. Se l'ereditarietà dell'isolamento torna, **questo test non
    /// fallisce: fa cadere l'intero processo di test con un trap**. È il prezzo per accorgersene
    /// qui invece che a device collegato.
    @Test("Il render block si può chiamare da un thread qualsiasi, non solo dal main")
    func renderBlockIsNotBoundToTheMainActor() async throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.5, frames: 4096))
        deck.play()

        let handoff = UnsafeHandoff(value: engine)
        let peak = try await Task.detached {
            let engine = handoff.value
            let buffer = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat, frameCapacity: 512
            )!
            _ = try engine.renderOffline(512, to: buffer)
            let samples = buffer.floatChannelData![0]
            return (0..<512).reduce(Float(0)) { max($0, abs(samples[$1])) }
        }.value

        #expect(abs(peak - 0.5) < 0.01)
    }

    // MARK: - Pitch bend e nudge

    /// La spinta si somma al fader senza spostarlo: è il gesto del dito sul piatto, e al rilascio
    /// la velocità torna dov'era.
    @Test("Il bend accelera senza toccare il fader, e al rilascio si torna indietro")
    func bendAddsToPitch() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.3, frames: 44_100))
        deck.pitchPercent = 2
        deck.setBend(3)
        #expect(deck.pitchPercent == 2, "il fader non si muove")
        #expect(abs(deck.rate - 1.05) < 1e-9)
        deck.play()

        _ = try render(engine, frames: 512)
        let afterBend = deck.positionSeconds
        #expect(abs(afterBend - 512 * 1.05 / Self.sampleRate) < 1e-6)

        deck.clearBend()
        #expect(abs(deck.rate - 1.02) < 1e-9)
        _ = try render(engine, frames: 512)
        #expect(abs(deck.positionSeconds - (afterBend + 512 * 1.02 / Self.sampleRate)) < 1e-6)
    }

    @Test("La spinta è limitata a ±3%")
    func bendIsClamped() {
        let deck = DeckEngine(format: format())
        deck.setBend(20)
        #expect(deck.bendPercent == 3)
        deck.setBend(-20)
        #expect(deck.bendPercent == -3)
    }

    @Test("Caricare una traccia azzera la spinta ma non il fader")
    func loadClearsBendNotPitch() {
        let deck = DeckEngine(format: format())
        deck.pitchPercent = -5
        deck.setBend(2)

        deck.load(constant(0.3, frames: 4_410))
        #expect(deck.bendPercent == 0)
        #expect(deck.pitchPercent == -5)
        #expect(abs(deck.rate - 0.95) < 1e-9)
    }

    @Test("Il nudge sposta la testina del passo esatto, senza cambiare il trasporto")
    func nudgeShiftsPlayhead() {
        let deck = DeckEngine(format: format())
        deck.load(constant(0.3, frames: 44_100))
        deck.seek(toSeconds: 0.5)

        deck.nudge(bySeconds: DeckEngine.nudgeSeconds)
        #expect(abs(deck.positionSeconds - 0.51) < 1e-6)
        #expect(deck.isPlaying == false, "il nudge non fa partire né fermare niente")

        deck.nudge(bySeconds: -DeckEngine.nudgeSeconds)
        #expect(abs(deck.positionSeconds - 0.5) < 1e-6)
    }

    @Test("Il nudge non esce dalla traccia")
    func nudgeStaysInsideTrack() {
        let deck = DeckEngine(format: format())
        deck.load(constant(0.3, frames: 44_100))

        deck.nudge(bySeconds: -1)
        #expect(deck.positionSeconds == 0)

        deck.seek(toSeconds: 1)
        deck.nudge(bySeconds: 1)
        #expect(abs(deck.positionSeconds - 1) < 1e-6)
    }

    // MARK: - Tasto CUE

    @Test("In play il CUE torna al cue e ferma il deck")
    func cueWhilePlayingGoesBack() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.5, frames: 44_100))
        deck.play()
        _ = try render(engine, frames: 512)
        #expect(deck.positionSeconds > 0)

        deck.pressCue()
        #expect(deck.isPlaying == false)
        #expect(deck.positionSeconds == 0)
    }

    @Test("In pausa altrove il CUE sposta il cue nella posizione corrente")
    func cueWhilePausedMovesCue() {
        let deck = DeckEngine(format: format())
        deck.load(constant(0.5, frames: 44_100))

        deck.seek(toSeconds: 0.4)
        deck.pressCue()
        #expect(abs(deck.cueSeconds - 0.4) < 1e-6)
        #expect(deck.isPlaying == false, "spostare il cue non fa partire niente")
        #expect(deck.isAtCue)
    }

    @Test("Il back cue torna al cue spostato, non all'inizio della traccia")
    func backCueUsesMovedCue() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.5, frames: 44_100))
        deck.seek(toSeconds: 0.4)
        deck.pressCue()

        deck.play()
        _ = try render(engine, frames: 512)
        deck.pressCue()
        #expect(deck.isPlaying == false)
        #expect(abs(deck.positionSeconds - 0.4) < 1e-6)
    }

    @Test("In pausa sul cue il tasto tenuto premuto suona, e al rilascio si torna al cue")
    func cuePreview() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.5, frames: 44_100))
        deck.seek(toSeconds: 0.2)
        deck.pressCue()
        #expect(abs(deck.cueSeconds - 0.2) < 1e-6)

        // Secondo colpo: adesso la testina è sul cue, quindi è un'anteprima.
        deck.pressCue()
        #expect(deck.isPlaying)
        #expect(deck.isPreviewingCue)

        _ = try render(engine, frames: 1024)
        #expect(deck.positionSeconds > 0.2)

        deck.releaseCue()
        #expect(deck.isPlaying == false)
        #expect(deck.isPreviewingCue == false)
        #expect(abs(deck.positionSeconds - 0.2) < 1e-6)
    }

    @Test("Un rilascio senza anteprima non ferma una riproduzione avviata dal play")
    func releaseWithoutPreviewDoesNothing() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.5, frames: 44_100))
        deck.play()
        _ = try render(engine, frames: 256)

        deck.releaseCue()
        #expect(deck.isPlaying, "il tasto CUE non era stato premuto: non c'è niente da chiudere")
    }

    @Test("Un play esplicito durante l'anteprima se ne prende il comando")
    func explicitTransportEndsPreview() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.5, frames: 44_100))
        deck.pressCue()
        #expect(deck.isPreviewingCue)

        _ = try render(engine, frames: 512)
        deck.pause()
        #expect(deck.isPreviewingCue == false)

        let stopped = deck.positionSeconds
        deck.releaseCue()
        #expect(deck.positionSeconds == stopped, "il rilascio non deve più riportare al cue")
    }

    @Test("Arrivati in fondo il CUE riporta al cue invece di piazzarlo sull'ultimo frame")
    func cueAtEndGoesBack() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.4, frames: 512))
        deck.play()
        _ = try render(engine, frames: 1024)
        #expect(deck.hasReachedEnd)

        deck.pressCue()
        #expect(deck.cueSeconds == 0)
        #expect(deck.positionSeconds == 0)
        #expect(deck.hasReachedEnd == false, "il seek riapre il deck al play")
    }

    @Test("Il cue si azzera caricando un'altra traccia")
    func cueResetsOnLoad() {
        let deck = DeckEngine(format: format())
        deck.load(constant(0.5, frames: 44_100))
        deck.seek(toSeconds: 0.6)
        deck.pressCue()
        #expect(abs(deck.cueSeconds - 0.6) < 1e-6)

        deck.load(constant(0.5, frames: 44_100))
        #expect(deck.cueSeconds == 0)
        #expect(deck.isPreviewingCue == false)
    }

    @Test("Senza traccia il CUE non fa niente")
    func cueOnEmptyDeck() {
        let deck = DeckEngine(format: format())
        deck.pressCue()
        deck.releaseCue()
        #expect(deck.cueSeconds == 0)
        #expect(deck.isPlaying == false)
    }

    @Test("Svuotare il deck lo zittisce")
    func unloadSilences() throws {
        let format = format()
        let deck = DeckEngine(format: format)
        let engine = try makeGraph(deck, format: format)
        defer { engine.stop() }

        deck.load(constant(0.5, frames: 4096))
        deck.play()
        _ = try render(engine, frames: 128)

        deck.unload()
        #expect(deck.hasTrack == false)
        let buffer = try render(engine, frames: 128)
        let samples = buffer.floatChannelData![0]
        for index in 0..<128 {
            #expect(samples[index] == 0)
        }
    }
}
