import Foundation
import Testing
@testable import DJKit

/// Il rilevamento del tempo si verifica su **click track sintetici a BPM noto**, non su musica
/// vera: un file musicale rende il test non riproducibile — dipende da come è masterizzato e da
/// dove è stato tagliato — e soprattutto non dice quale sia la risposta giusta, che è proprio la
/// cosa che il test dovrebbe sapere.
@Suite("Rilevamento del tempo")
struct TempoAnalyzerTests {
    private static let sampleRate = 44_100.0

    /// Un colpo percussivo: rumore filtrato con attacco istantaneo e coda breve, cioè le due
    /// caratteristiche su cui lavora lo spectral flux.
    private static func click(amplitude: Float, decaySeconds: Double, seed: inout UInt64) -> [Float] {
        let count = Int(sampleRate * decaySeconds)
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            // Generatore lineare congruente: deterministico, quindi il test dà lo stesso
            // risultato a ogni esecuzione.
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = Float(Int64(bitPattern: seed >> 11)) / Float(1 << 52) - 1
            let envelope = Float(exp(-Double(index) / (sampleRate * decaySeconds * 0.15)))
            samples[index] = noise * envelope * amplitude
        }
        return samples
    }

    /// Click track a 4/4: colpo forte sull'uno, colpi più leggeri sugli altri quarti.
    ///
    /// Il colpo dell'uno è quello che permette anche di verificare il downbeat, non solo il
    /// periodo.
    private static func clickTrack(
        bpm: Double,
        seconds: Double,
        startSeconds: Double,
        offbeats: Bool = false
    ) -> [Float] {
        var seed: UInt64 = 0x5EED
        let downbeat = click(amplitude: 1.0, decaySeconds: 0.12, seed: &seed)
        let beat = click(amplitude: 0.45, decaySeconds: 0.06, seed: &seed)
        let offbeat = click(amplitude: 0.18, decaySeconds: 0.03, seed: &seed)

        var track = [Float](repeating: 0, count: Int(sampleRate * seconds))
        let beatDuration = 60 / bpm
        var index = 0
        var position = startSeconds

        while position < seconds {
            let source = index % 4 == 0 ? downbeat : beat
            mix(source, into: &track, atSeconds: position)
            if offbeats {
                mix(offbeat, into: &track, atSeconds: position + beatDuration / 2)
            }
            position += beatDuration
            index += 1
        }
        return track
    }

    private static func mix(_ source: [Float], into track: inout [Float], atSeconds seconds: Double) {
        let start = Int(seconds * sampleRate)
        for offset in 0..<source.count {
            let target = start + offset
            guard target >= 0, target < track.count else { continue }
            track[target] += source[offset]
        }
    }

    // MARK: - BPM

    @Test(
        "Il BPM di un click track si ritrova entro mezzo BPM",
        arguments: [120.0, 128.0, 174.0]
    )
    func detectsKnownTempo(bpm: Double) throws {
        let track = Self.clickTrack(bpm: bpm, seconds: 60, startSeconds: 0.3)
        let estimate = try #require(
            TempoAnalyzer.analyze(mono: track, sampleRate: Self.sampleRate)
        )
        #expect(abs(estimate.bpm - bpm) < 0.5, "rilevati \(estimate.bpm) invece di \(bpm)")
    }

    @Test(
        "I charleston in levare non fanno raddoppiare il tempo",
        arguments: [120.0, 128.0]
    )
    func offbeatsDoNotDoubleTempo(bpm: Double) throws {
        let track = Self.clickTrack(bpm: bpm, seconds: 60, startSeconds: 0.5, offbeats: true)
        let estimate = try #require(
            TempoAnalyzer.analyze(mono: track, sampleRate: Self.sampleRate)
        )
        #expect(abs(estimate.bpm - bpm) < 0.5, "rilevati \(estimate.bpm) invece di \(bpm)")
    }

    @Test("Su un brano lungo il BPM resta preciso al centesimo")
    func longTrackKeepsPrecision() throws {
        let track = Self.clickTrack(bpm: 124.0, seconds: 300, startSeconds: 1.0)
        let estimate = try #require(
            TempoAnalyzer.analyze(mono: track, sampleRate: Self.sampleRate)
        )
        // Con la raffinatura sul ritardo lungo l'errore deve stare ben sotto il decimo: è quello
        // che tiene la griglia allineata anche in fondo al pezzo.
        #expect(abs(estimate.bpm - 124.0) < 0.05, "rilevati \(estimate.bpm)")
    }

    // MARK: - Griglia

    @Test("Il primo downbeat cade sul colpo forte")
    func findsDownbeat() throws {
        let start = 0.72
        let track = Self.clickTrack(bpm: 128.0, seconds: 90, startSeconds: start)
        let estimate = try #require(
            TempoAnalyzer.analyze(mono: track, sampleRate: Self.sampleRate)
        )
        let grid = try #require(estimate.beatgrid)

        // L'offset è il primo downbeat, quindi cade dentro la prima misura.
        #expect(estimate.beatgridOffsetSeconds >= 0)
        #expect(estimate.beatgridOffsetSeconds < grid.barDuration)
        #expect(
            abs(estimate.beatgridOffsetSeconds - start) < 0.03,
            "downbeat a \(estimate.beatgridOffsetSeconds) invece di \(start)"
        )
    }

    @Test("Le battute della griglia cadono sui colpi per tutta la traccia")
    func gridStaysAlignedToTheEnd() throws {
        let bpm = 130.0
        let start = 0.4
        let track = Self.clickTrack(bpm: bpm, seconds: 240, startSeconds: start)
        let estimate = try #require(
            TempoAnalyzer.analyze(mono: track, sampleRate: Self.sampleRate)
        )
        let grid = try #require(estimate.beatgrid)

        // Ultimo colpo del brano: è dove l'errore sul BPM si accumula tutto.
        let lastBeat = Int(((240 - start) / (60 / bpm)).rounded(.down))
        let expected = start + Double(lastBeat) * 60 / bpm
        let position = grid.beatPosition(atSeconds: expected)
        let distance = abs(position - position.rounded()) * grid.beatDuration
        #expect(distance < 0.02, "in fondo la griglia sbaglia di \(distance) s")
    }

    // MARK: - Casi limite

    @Test("Su due secondi di audio non si inventa un tempo")
    func refusesTooShortAudio() {
        let track = [Float](repeating: 0, count: Int(Self.sampleRate * 2))
        #expect(TempoAnalyzer.analyze(mono: track, sampleRate: Self.sampleRate) == nil)
    }

    @Test("Il silenzio non produce un BPM")
    func refusesSilence() {
        let track = [Float](repeating: 0, count: Int(Self.sampleRate * 60))
        #expect(TempoAnalyzer.analyze(mono: track, sampleRate: Self.sampleRate) == nil)
    }
}
