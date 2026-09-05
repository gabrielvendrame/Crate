import Testing
@testable import DJKit

@Suite("Traccia in memoria per il thread audio")
struct DecodedTrackTests {
    private func ramp(count: Int, channels: Int) -> DecodedAudio {
        let data = (0..<channels).map { channel in
            (0..<count).map { Float($0 + channel * 1000) }
        }
        return DecodedAudio(channels: data, sampleRate: 44_100, frameCount: count)
    }

    @Test("Conserva i sample di ogni canale")
    func keepsSamples() {
        let track = DecodedTrack(audio: ramp(count: 100, channels: 2))
        #expect(track.frameCount == 100)
        #expect(track.channelCount == 2)
        #expect(track.sample(channel: 0, frame: 0) == 0)
        #expect(track.sample(channel: 0, frame: 99) == 99)
        #expect(track.sample(channel: 1, frame: 5) == 1005)
    }

    /// È la cornice che permette all'interpolazione di leggere `i-1 … i+2` senza controlli di
    /// bordo: se qui comparisse un valore diverso da zero, il primo e l'ultimo sample della
    /// traccia suonerebbero sporchi.
    @Test("Fuori dalla traccia legge zeri, non memoria altrui")
    func guardFramesAreSilent() {
        let track = DecodedTrack(audio: ramp(count: 64, channels: 2))
        #expect(track.sample(channel: 0, frame: -1) == 0)
        #expect(track.sample(channel: 0, frame: -4) == 0)
        #expect(track.sample(channel: 0, frame: 64) == 0)
        #expect(track.sample(channel: 1, frame: 66) == 0)
    }

    @Test("Un file mono resta a un canale")
    func monoStaysMono() {
        let track = DecodedTrack(audio: ramp(count: 32, channels: 1))
        #expect(track.channelCount == 1)
        #expect(track.sample(channel: 1, frame: 3) == 3, "il canale mancante ricade sul primo")
    }

    @Test("Oltre due canali si tronca all'uscita stereo")
    func truncatesToStereo() {
        let track = DecodedTrack(audio: ramp(count: 32, channels: 6))
        #expect(track.channelCount == 2)
    }

    @Test("La durata viene dalla frequenza del file")
    func duration() {
        let track = DecodedTrack(audio: ramp(count: 44_100, channels: 2))
        #expect(abs(track.durationSeconds - 1) < 1e-9)
    }

    @Test("Una traccia vuota non alloca fuori misura né rompe i puntatori")
    func emptyTrack() {
        let track = DecodedTrack(
            audio: DecodedAudio(channels: [[]], sampleRate: 44_100, frameCount: 0)
        )
        #expect(track.frameCount == 0)
        #expect(track.durationSeconds == 0)
        #expect(track.sample(channel: 0, frame: 0) == 0)
    }
}
