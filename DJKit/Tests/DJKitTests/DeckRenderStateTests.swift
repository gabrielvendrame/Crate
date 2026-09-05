import AVFoundation
import Testing
@testable import DJKit

/// Buffer di uscita finto: fa girare il render callback senza device audio, come lo chiamerebbe
/// `AVAudioSourceNode`. È il modo di verificare il varispeed e il playhead con `swift test`,
/// senza dipendere dall'hardware.
private final class RenderProbe {
    let capacity: Int
    private let list: UnsafeMutableAudioBufferListPointer
    private let left: UnsafeMutablePointer<Float>
    private let right: UnsafeMutablePointer<Float>

    init(capacity: Int) {
        self.capacity = capacity
        list = AudioBufferList.allocate(maximumBuffers: 2)
        left = .allocate(capacity: capacity)
        right = .allocate(capacity: capacity)
        left.initialize(repeating: .nan, count: capacity)
        right.initialize(repeating: .nan, count: capacity)
        let bytes = UInt32(capacity * MemoryLayout<Float>.size)
        list[0] = AudioBuffer(
            mNumberChannels: 1, mDataByteSize: bytes, mData: UnsafeMutableRawPointer(left)
        )
        list[1] = AudioBuffer(
            mNumberChannels: 1, mDataByteSize: bytes, mData: UnsafeMutableRawPointer(right)
        )
    }

    deinit {
        left.deallocate()
        right.deallocate()
        free(list.unsafeMutablePointer)
    }

    /// Restituisce il flag di silenzio che il callback ha alzato.
    @discardableResult
    func render(_ state: DeckRenderState, frames: Int? = nil) -> Bool {
        var silence = ObjCBool(false)
        _ = withUnsafeMutablePointer(to: &silence) { flag in
            state.render(
                frameCount: frames ?? capacity,
                into: list.unsafeMutablePointer,
                isSilence: flag
            )
        }
        return silence.boolValue
    }

    func left(_ index: Int) -> Float { left[index] }
    func right(_ index: Int) -> Float { right[index] }
}

/// Tiene in vita traccia e descrittore per la durata di un test, come fa `DeckEngine` sul main.
private final class LoadedFixture {
    let track: DecodedTrack
    let reference: UnsafeMutablePointer<DeckTrackRef>

    init(frameCount: Int, channels: Int = 2, baseStep: Double = 1, sampleRate: Double = 44_100) {
        let data = (0..<channels).map { channel in
            (0..<frameCount).map { Float($0) * (channel == 0 ? 1 : -1) }
        }
        track = DecodedTrack(
            audio: DecodedAudio(channels: data, sampleRate: sampleRate, frameCount: frameCount)
        )
        reference = .allocate(capacity: 1)
        reference.initialize(
            to: DeckTrackRef(
                left: track.base(ofChannel: 0),
                right: track.channelCount > 1 ? track.base(ofChannel: 1) : nil,
                frameCount: track.frameCount,
                baseStep: baseStep,
                sampleRate: sampleRate
            )
        )
    }

    deinit {
        reference.deinitialize(count: 1)
        reference.deallocate()
    }

    var bits: UInt { UInt(bitPattern: UnsafeMutableRawPointer(reference)) }
}

@Suite("Render callback del deck")
struct DeckRenderStateTests {
    private func prepared(
        _ fixture: LoadedFixture,
        playing: Bool = true,
        fromFrame: Double = 0
    ) -> DeckRenderState {
        let state = DeckRenderState()
        _ = state.exchangeTrackRef(fixture.bits)
        state.requestSeek(toFrame: fromFrame)
        state.setPlaying(playing)
        return state
    }

    @Test("A pitch zero esce il sample esatto, uno per frame")
    func unityRate() {
        let fixture = LoadedFixture(frameCount: 1024)
        let state = prepared(fixture)
        let probe = RenderProbe(capacity: 128)

        #expect(probe.render(state) == false)
        for index in 0..<128 {
            #expect(probe.left(index) == Float(index))
            #expect(probe.right(index) == -Float(index))
        }
        #expect(abs(state.playheadFrame - 128) < 1e-9)
    }

    @Test("Il playhead riprende da dove il buffer precedente si era fermato")
    func continuesAcrossBuffers() {
        let fixture = LoadedFixture(frameCount: 1024)
        let state = prepared(fixture)
        let probe = RenderProbe(capacity: 64)

        probe.render(state)
        probe.render(state)
        #expect(probe.left(0) == 64)
        #expect(abs(state.playheadFrame - 128) < 1e-9)
    }

    /// Il varispeed **è** il passo del playhead: a +8% il rate vale 1,08 e il playhead consuma
    /// 1,08 frame di traccia per ogni frame di uscita. Su una rampa l'interpolazione è esatta,
    /// quindi il valore atteso si può scrivere in chiaro.
    @Test("Il rate cambia il passo del playhead, non la catena audio", arguments: [0.5, 1.08, 2.0])
    func varispeed(rate: Double) {
        let fixture = LoadedFixture(frameCount: 4096)
        let state = prepared(fixture, fromFrame: 100)
        state.setRate(rate)
        let probe = RenderProbe(capacity: 64)

        probe.render(state)
        for index in 0..<64 {
            let expected = Float(100 + rate * Double(index))
            #expect(abs(probe.left(index) - expected) < 0.01)
        }
        #expect(abs(state.playheadFrame - (100 + rate * 64)) < 1e-6)
    }

    /// Il resampling verso il device è lo stesso meccanismo: un file a 44,1 kHz su un grafo a
    /// 48 kHz avanza di 0,919 frame per frame di uscita, senza nessun nodo in più.
    @Test("La conversione di frequenza passa dallo stesso passo frazionario")
    func sampleRateConversion() {
        let fixture = LoadedFixture(frameCount: 4096, baseStep: 44_100 / 48_000)
        let state = prepared(fixture, fromFrame: 10)
        let probe = RenderProbe(capacity: 32)

        probe.render(state)
        for index in 0..<32 {
            let expected = Float(10 + 44_100 / 48_000 * Double(index))
            #expect(abs(probe.left(index) - expected) < 0.01)
        }
    }

    @Test("In pausa esce silenzio e la posizione non si muove")
    func pausedIsSilent() {
        let fixture = LoadedFixture(frameCount: 1024)
        let state = prepared(fixture, playing: false, fromFrame: 200)
        let probe = RenderProbe(capacity: 32)

        #expect(probe.render(state) == true)
        for index in 0..<32 { #expect(probe.left(index) == 0) }
        #expect(abs(state.playheadFrame - 200) < 1e-9)
    }

    @Test("Un deck vuoto non suona niente")
    func emptyDeckIsSilent() {
        let state = DeckRenderState()
        state.setPlaying(true)
        let probe = RenderProbe(capacity: 16)

        #expect(probe.render(state) == true)
        for index in 0..<16 { #expect(probe.left(index) == 0) }
    }

    @Test("Alla fine della traccia si ferma da sé e azzera il resto del buffer")
    func stopsAtEnd() {
        let fixture = LoadedFixture(frameCount: 100)
        let state = prepared(fixture, fromFrame: 90)
        let probe = RenderProbe(capacity: 32)

        probe.render(state)
        #expect(probe.left(9) == 99)
        #expect(probe.left(10) == 0, "oltre la fine il buffer va azzerato, non lasciato sporco")
        #expect(probe.left(31) == 0)
        #expect(state.isPlaying == false)
        #expect(state.hasReachedEnd == true)
        #expect(abs(state.playheadFrame - 100) < 1e-9)
    }

    @Test("Il seek viene adottato al buffer successivo e visto subito dalla UI")
    func seekIsAdopted() {
        let fixture = LoadedFixture(frameCount: 4096)
        let state = prepared(fixture)
        let probe = RenderProbe(capacity: 16)

        probe.render(state)
        state.requestSeek(toFrame: 500)
        // La posizione pubblicata cambia prima del render: la testina nella UI non aspetta il
        // buffer successivo per seguire il dito.
        #expect(abs(state.playheadFrame - 500) < 1e-9)

        probe.render(state)
        #expect(probe.left(0) == 500)
        #expect(abs(state.playheadFrame - 516) < 1e-9)
    }

    @Test("Cambiare traccia riparte da zero senza sporcare la nuova")
    func trackSwapRestarts() {
        let first = LoadedFixture(frameCount: 1024)
        let second = LoadedFixture(frameCount: 1024)
        let state = prepared(first, fromFrame: 700)
        let probe = RenderProbe(capacity: 8)

        probe.render(state)
        #expect(probe.left(0) == 700)

        let previous = state.exchangeTrackRef(second.bits)
        #expect(previous == first.bits, "lo scambio restituisce il descrittore da mandare in pensione")
        state.setPlaying(true)
        probe.render(state)
        #expect(probe.left(0) == 0)
    }

    @Test("Un file mono esce su entrambi i canali")
    func monoFeedsBothChannels() {
        let fixture = LoadedFixture(frameCount: 512, channels: 1)
        let state = prepared(fixture)
        let probe = RenderProbe(capacity: 16)

        probe.render(state)
        for index in 0..<16 {
            #expect(probe.left(index) == Float(index))
            #expect(probe.right(index) == Float(index))
        }
    }

    @Test("Il contatore di render avanza a ogni buffer, anche in pausa")
    func tickAdvances() {
        let fixture = LoadedFixture(frameCount: 512)
        let state = prepared(fixture, playing: false)
        let probe = RenderProbe(capacity: 8)

        let before = state.tick
        probe.render(state)
        probe.render(state)
        #expect(state.tick == before + 2, "è il segnale che il main aspetta per liberare la traccia vecchia")
    }
}
