import Foundation
import Testing
@testable import DJKit

@Suite("Calcolo dei peaks")
struct PeaksBuilderTests {
    private let sampleRate = 44_100.0

    /// Sinusoide a fondo scala: ampiezza 1, quindi RMS atteso 0,707 nella sua banda.
    private func sine(frequency: Double, seconds: Double, amplitude: Float = 1) -> DecodedAudio {
        let count = Int(sampleRate * seconds)
        var samples = [Float](repeating: 0, count: count)
        for index in 0..<count {
            samples[index] = amplitude * Float(sin(2 * .pi * frequency * Double(index) / sampleRate))
        }
        return DecodedAudio(channels: [samples], sampleRate: sampleRate, frameCount: count)
    }

    /// Media dei livelli di banda escludendo i bordi, dove la finestra pesca nel silenzio.
    private func middleAverage(_ level: PeaksLevel, _ band: KeyPath<PeakBin, Float>) -> Float {
        let margin = max(1, level.count / 10)
        let slice = level.bins[margin..<(level.count - margin)]
        return slice.reduce(0) { $0 + $1[keyPath: band] } / Float(slice.count)
    }

    @Test("Ogni livello ha il numero di bin che gli spetta")
    func levelSizes() {
        let audio = sine(frequency: 1_000, seconds: 2)
        let peaks = PeaksBuilder.build(audio)

        #expect(peaks.levels.map(\.binSize) == PeaksBuilder.binSizes)
        #expect(peaks.frameCount == audio.frameCount)
        for level in peaks.levels {
            let expected = PeaksBuilder.binCount(frameCount: audio.frameCount, binSize: level.binSize)
            #expect(level.count == expected, "livello \(level.binSize)")
        }
    }

    @Test("Una sinusoide a fondo scala riempie la waveform da −1 a +1")
    func shapeMatchesAmplitude() throws {
        let peaks = PeaksBuilder.build(sine(frequency: 1_000, seconds: 1))
        let level = try #require(peaks.level(binSize: 64))
        let middle = level.bins[level.count / 2]

        #expect(abs(middle.maximum - 1) < 0.02)
        #expect(abs(middle.minimum + 1) < 0.02)
    }

    @Test("Un basso a 60 Hz finisce nella banda low")
    func lowBandDominates() throws {
        let peaks = PeaksBuilder.build(sine(frequency: 60, seconds: 1))
        let level = try #require(peaks.level(binSize: PeaksBuilder.bandBinSize))

        let low = middleAverage(level, \.low)
        #expect(abs(low - 0.707) < 0.06, "low = \(low)")
        #expect(middleAverage(level, \.mid) < 0.05)
        #expect(middleAverage(level, \.high) < 0.05)
    }

    @Test("Un tono a 1 kHz finisce nella banda mid")
    func midBandDominates() throws {
        let peaks = PeaksBuilder.build(sine(frequency: 1_000, seconds: 1))
        let level = try #require(peaks.level(binSize: PeaksBuilder.bandBinSize))

        let mid = middleAverage(level, \.mid)
        #expect(abs(mid - 0.707) < 0.06, "mid = \(mid)")
        #expect(middleAverage(level, \.low) < 0.05)
        #expect(middleAverage(level, \.high) < 0.05)
    }

    @Test("Un tono a 10 kHz finisce nella banda high")
    func highBandDominates() throws {
        let peaks = PeaksBuilder.build(sine(frequency: 10_000, seconds: 1))
        let level = try #require(peaks.level(binSize: PeaksBuilder.bandBinSize))

        let high = middleAverage(level, \.high)
        #expect(abs(high - 0.707) < 0.06, "high = \(high)")
        #expect(middleAverage(level, \.low) < 0.05)
        #expect(middleAverage(level, \.mid) < 0.05)
    }

    @Test("Il silenzio non colora nulla")
    func silenceStaysSilent() throws {
        let count = 44_100
        let audio = DecodedAudio(
            channels: [[Float](repeating: 0, count: count)],
            sampleRate: sampleRate,
            frameCount: count
        )
        let peaks = PeaksBuilder.build(audio)
        let level = try #require(peaks.level(binSize: 64))

        for bin in level.bins {
            #expect(bin.minimum == 0)
            #expect(bin.maximum == 0)
            #expect(bin.low == 0)
            #expect(bin.mid == 0)
            #expect(bin.high == 0)
        }
    }

    @Test("La sagoma di un livello grosso coincide con quella dei bin fini che contiene")
    func levelsAgreeOnShape() throws {
        // Rumore riproducibile: un generatore congruenziale, non `random()`, così un fallimento
        // si può rieseguire identico.
        var state: UInt64 = 0x5EED
        var samples = [Float](repeating: 0, count: 300_000)
        for index in samples.indices {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            samples[index] = Float(Int32(truncatingIfNeeded: state >> 33)) / Float(Int32.max)
        }
        let audio = DecodedAudio(channels: [samples], sampleRate: sampleRate, frameCount: samples.count)
        let peaks = PeaksBuilder.build(audio)

        let fine = try #require(peaks.level(binSize: 64))
        for coarseSize in [256, 1_024, 4_096] {
            let coarse = try #require(peaks.level(binSize: coarseSize))
            let factor = coarseSize / 64

            for index in stride(from: 0, to: coarse.count, by: max(1, coarse.count / 20)) {
                let start = index * factor
                let end = min(start + factor, fine.count)
                let expectedMin = fine.bins[start..<end].map(\.minimum).min() ?? 0
                let expectedMax = fine.bins[start..<end].map(\.maximum).max() ?? 0

                #expect(coarse.bins[index].minimum == expectedMin, "livello \(coarseSize), bin \(index)")
                #expect(coarse.bins[index].maximum == expectedMax, "livello \(coarseSize), bin \(index)")
            }
        }
    }

    @Test("La scelta del livello segue la scala di disegno")
    func levelSelection() {
        let peaks = PeaksBuilder.build(sine(frequency: 1_000, seconds: 1))

        // Overview di 5 minuti su 1400 px: circa 9450 frame per pixel, il livello più grosso.
        #expect(peaks.level(framesPerPixel: 9_450).binSize == 4_096)
        // Vista zoomata su 8 secondi: circa 250 frame per pixel.
        #expect(peaks.level(framesPerPixel: 250).binSize == 64)
        #expect(peaks.level(framesPerPixel: 1_100).binSize == 1_024)
        // Più zoom di quanto la cache possa dare: si prende comunque il livello più fine.
        #expect(peaks.level(framesPerPixel: 10).binSize == 64)
    }
}
