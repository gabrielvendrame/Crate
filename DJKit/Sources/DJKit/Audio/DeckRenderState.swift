import AVFoundation
import Synchronization

/// Il punto d'incontro fra il main actor e il thread audio, e l'unico pezzo di codice che gira
/// dentro il render callback.
///
/// Tutto ciò che i due thread si scambiano passa da un'atomica: la traccia (come puntatore al
/// descrittore), il rate, play/pausa, la richiesta di seek in una direzione e la posizione
/// raggiunta nell'altra. Nessun lock, nessuna coda, nessuna allocazione.
///
/// **Le regole del callback**, da rileggere prima di toccare `render`: niente allocazioni, niente
/// lock, niente ARC, niente Objective-C, niente `print`. Anche una sola violazione produce un
/// glitch che si sente solo a caso e non si vede in nessun test.
final class DeckRenderState: @unchecked Sendable {
    /// Stato che appartiene **solo** al thread audio: la posizione fra un buffer e il successivo,
    /// il descrittore adottato e l'ultimo seek visto. Sta in memoria raw perché mutarlo da dentro
    /// il callback non deve passare da ARC né dall'isolamento degli actor.
    private struct Scratch {
        var playhead: Double
        var seenSeek: UInt64
        var refBits: UInt
        var ref: DeckTrackRef
    }

    // Main → audio.
    /// Bit del puntatore al `DeckTrackRef` corrente, 0 quando il deck è vuoto.
    private let trackRefBits = Atomic<UInt>(0)
    private let rateBits = Atomic<UInt64>((1.0 as Double).bitPattern)
    private let playing = Atomic<Bool>(false)
    private let seekTargetBits = Atomic<UInt64>((0.0 as Double).bitPattern)
    /// Cambia a ogni seek: è così che il callback distingue "nuova richiesta" da "stesso valore
    /// di prima", senza che il main debba scrivere il playhead che il callback sta aggiornando.
    private let seekCounter = Atomic<UInt64>(0)
    /// Frequenza del file in suono, ripetuta qui perché la posizione in secondi va potuta leggere
    /// da qualsiasi thread — il renderer Metal la chiede 60 volte al secondo.
    private let sampleRateBits = Atomic<UInt64>((0.0 as Double).bitPattern)

    // Audio → main.
    private let playheadBits = Atomic<UInt64>((0.0 as Double).bitPattern)
    /// Avanza alla fine di ogni render. Il main lo usa per sapere quando il thread audio ha
    /// smesso di guardare il descrittore vecchio e la memoria si può liberare.
    private let renderTick = Atomic<UInt64>(0)
    /// Il callback ha raggiunto la fine della traccia e si è fermato da sé.
    private let endReached = Atomic<Bool>(false)

    private let scratch: UnsafeMutablePointer<Scratch>

    init() {
        scratch = .allocate(capacity: 1)
        scratch.initialize(
            to: Scratch(
                playhead: 0,
                seenSeek: 0,
                refBits: 0,
                ref: DeckTrackRef(
                    left: nil, right: nil, frameCount: 0, baseStep: 1, sampleRate: 0
                )
            )
        )
    }

    deinit {
        scratch.deinitialize(count: 1)
        scratch.deallocate()
    }

    // MARK: - Lato main

    /// Mette in suono un nuovo descrittore e restituisce i bit di quello sostituito, che il
    /// chiamante deve mandare in pensione (non liberare subito: il callback può averlo in mano).
    func exchangeTrackRef(_ bits: UInt) -> UInt {
        endReached.store(false, ordering: .relaxed)
        return trackRefBits.exchange(bits, ordering: .releasing)
    }

    var currentTrackRefBits: UInt { trackRefBits.load(ordering: .relaxed) }

    func setSampleRate(_ value: Double) {
        sampleRateBits.store(value.bitPattern, ordering: .relaxed)
    }

    /// Posizione della testina in secondi di traccia, leggibile da qualsiasi thread: due letture
    /// atomiche e una divisione.
    var positionSeconds: Double {
        let rate = Double(bitPattern: sampleRateBits.load(ordering: .relaxed))
        guard rate > 0 else { return 0 }
        return playheadFrame / rate
    }

    var isPlaying: Bool { playing.load(ordering: .relaxed) }

    func setPlaying(_ value: Bool) {
        if value { endReached.store(false, ordering: .relaxed) }
        playing.store(value, ordering: .relaxed)
    }

    var hasReachedEnd: Bool { endReached.load(ordering: .relaxed) }

    /// Rapporto di velocità: 1 è il pitch a zero. Include già il varispeed, non la conversione di
    /// frequenza, che sta in `DeckTrackRef.baseStep`.
    func setRate(_ value: Double) {
        rateBits.store(value.bitPattern, ordering: .relaxed)
    }

    /// Frame frazionario a cui si trova la testina.
    var playheadFrame: Double {
        Double(bitPattern: playheadBits.load(ordering: .acquiring))
    }

    /// Sposta la testina. Il playhead visibile si aggiorna subito, così la UI non aspetta il
    /// prossimo buffer per mostrare dove è finito il dito.
    func requestSeek(toFrame frame: Double) {
        let target = max(0, frame)
        seekTargetBits.store(target.bitPattern, ordering: .relaxed)
        playheadBits.store(target.bitPattern, ordering: .releasing)
        endReached.store(false, ordering: .relaxed)
        _ = seekCounter.wrappingAdd(1, ordering: .releasing)
    }

    var tick: UInt64 { renderTick.load(ordering: .acquiring) }

    // MARK: - Lato audio (thread real-time)

    func render(
        frameCount: Int,
        into audioBufferList: UnsafeMutablePointer<AudioBufferList>,
        isSilence: UnsafeMutablePointer<ObjCBool>
    ) -> OSStatus {
        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        let out0 = buffers.count > 0
            ? buffers[0].mData?.assumingMemoryBound(to: Float.self) : nil
        let out1 = buffers.count > 1
            ? buffers[1].mData?.assumingMemoryBound(to: Float.self) : nil

        adoptTrackRef()
        adoptSeek()

        let ref = scratch.pointee.ref
        var playhead = max(0, scratch.pointee.playhead)
        var produced = 0

        if playing.load(ordering: .relaxed), ref.frameCount > 0, let source = ref.left {
            let isMono = ref.right == nil
            let right = ref.right ?? source
            // Il passo non può essere negativo: il playhead uscirebbe dalla cornice di zeri e
            // leggerebbe memoria di qualcun altro. Un controllo per buffer, non per sample.
            let step = max(0, ref.baseStep * Double(bitPattern: rateBits.load(ordering: .relaxed)))
            let limit = Double(ref.frameCount)

            while produced < frameCount, playhead < limit {
                let index = Int(playhead)
                let fraction = Float(playhead - Double(index))
                let left = CubicInterpolator.sample(
                    source[index - 1], source[index], source[index + 1], source[index + 2],
                    fraction
                )
                out0?[produced] = left
                if let out1 {
                    out1[produced] = isMono
                        ? left
                        : CubicInterpolator.sample(
                            right[index - 1], right[index], right[index + 1], right[index + 2],
                            fraction
                        )
                }
                playhead += step
                produced += 1
            }

            if playhead >= limit {
                // Fine della traccia: si ferma qui, come un piatto che arriva in fondo al solco.
                playhead = limit
                playing.store(false, ordering: .relaxed)
                endReached.store(true, ordering: .relaxed)
            }
        }

        if produced < frameCount {
            var index = produced
            while index < frameCount {
                out0?[index] = 0
                out1?[index] = 0
                index += 1
            }
        }

        scratch.pointee.playhead = playhead
        playheadBits.store(playhead.bitPattern, ordering: .releasing)
        isSilence.pointee = ObjCBool(produced == 0)
        // Per ultimo: il main legge questo contatore per sapere che il descrittore vecchio non è
        // più in uso, quindi va alzato quando il render ha davvero finito di leggerlo.
        _ = renderTick.wrappingAdd(1, ordering: .releasing)
        return noErr
    }

    /// Adotta il descrittore pubblicato dal main, se è cambiato. Copiarlo nello scratch evita di
    /// rileggere memoria condivisa a ogni sample.
    private func adoptTrackRef() {
        let bits = trackRefBits.load(ordering: .acquiring)
        guard bits != scratch.pointee.refBits else { return }
        scratch.pointee.refBits = bits

        if let pointer = UnsafeMutablePointer<DeckTrackRef>(bitPattern: bits) {
            scratch.pointee.ref = pointer.pointee
        } else {
            // Deck svuotato. I campi si azzerano a mano invece di assegnare un valore statico:
            // il primo accesso a una `static let` farebbe partire l'inizializzazione lazy, che
            // nel callback è una chiamata di runtime in più.
            scratch.pointee.ref.left = nil
            scratch.pointee.ref.right = nil
            scratch.pointee.ref.frameCount = 0
            scratch.pointee.ref.sampleRate = 0
        }
        // La posizione pubblicata non si tocca qui: la scrive la fine del render, quando un
        // eventuale seek arrivato nello stesso istante è già stato adottato.
        scratch.pointee.playhead = 0
    }

    private func adoptSeek() {
        let counter = seekCounter.load(ordering: .acquiring)
        guard counter != scratch.pointee.seenSeek else { return }
        scratch.pointee.seenSeek = counter
        scratch.pointee.playhead = Double(bitPattern: seekTargetBits.load(ordering: .relaxed))
    }
}
