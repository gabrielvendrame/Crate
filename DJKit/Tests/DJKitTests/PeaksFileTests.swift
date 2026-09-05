import Foundation
import Testing
@testable import DJKit

@Suite("Formato del file peaks")
struct PeaksFileTests {

    /// Peaks finti ma realistici: quattro livelli con il rapporto 4× fra l'uno e l'altro.
    private func makePeaks(frameCount: Int = 44_100) -> Peaks {
        var levels = [PeaksLevel]()
        for binSize in PeaksBuilder.binSizes {
            let count = PeaksBuilder.binCount(frameCount: frameCount, binSize: binSize)
            var bins = [PeakBin]()
            for index in 0..<count {
                let phase = Float(index) / Float(max(1, count))
                bins.append(
                    PeakBin(
                        minimum: -phase,
                        maximum: phase * 0.8,
                        low: phase,
                        mid: 1 - phase,
                        high: phase * 0.25
                    )
                )
            }
            levels.append(PeaksLevel(binSize: binSize, bins: bins))
        }
        return Peaks(sampleRate: 44_100, frameCount: frameCount, channelCount: 2, levels: levels)
    }

    @Test("Scrittura e rilettura restituiscono gli stessi valori entro la quantizzazione")
    func roundTrip() throws {
        let original = makePeaks()
        let decoded = try PeaksFile.decode(PeaksFile.encode(original))

        #expect(decoded.sampleRate == original.sampleRate)
        #expect(decoded.frameCount == original.frameCount)
        #expect(decoded.channelCount == original.channelCount)
        #expect(decoded.levels.count == original.levels.count)

        for (source, target) in zip(original.levels, decoded.levels) {
            #expect(source.binSize == target.binSize)
            #expect(source.count == target.count)
            for (a, b) in zip(source.bins, target.bins) {
                #expect(abs(a.minimum - b.minimum) < 0.01)
                #expect(abs(a.maximum - b.maximum) < 0.01)
                #expect(abs(a.low - b.low) < 0.01)
                #expect(abs(a.mid - b.mid) < 0.01)
                #expect(abs(a.high - b.high) < 0.01)
            }
        }
    }

    @Test("Il giro completo passa anche dal disco")
    func roundTripOnDisk() throws {
        let url = URL(filePath: NSTemporaryDirectory())
            .appending(path: "crate-\(UUID().uuidString).peaks")
        defer { try? FileManager.default.removeItem(at: url) }

        let original = makePeaks(frameCount: 200_000)
        try PeaksFile.write(original, to: url)
        let decoded = try PeaksFile.read(from: url)

        #expect(decoded.frameCount == original.frameCount)
        for (source, target) in zip(original.levels, decoded.levels) {
            #expect(source.count == target.count)
        }
    }

    @Test("Lo zero resta esattamente zero dopo il giro")
    func zeroSurvivesQuantisation() {
        #expect(PeaksFile.encodeSigned(0) == 128)
        #expect(PeaksFile.decodeSigned(128) == 0)
        #expect(PeaksFile.encodeUnit(0) == 0)
        #expect(PeaksFile.decodeUnit(0) == 0)
    }

    @Test("Gli estremi della scala non tracimano")
    func extremesAreClamped() {
        #expect(PeaksFile.encodeSigned(2) == 255)
        #expect(PeaksFile.encodeSigned(-2) == 1)
        #expect(PeaksFile.encodeUnit(3) == 255)
        #expect(abs(PeaksFile.decodeUnit(255) - 1) < 0.001)
    }

    @Test("Un file con firma sbagliata viene rifiutato")
    func rejectsForeignFile() {
        let junk = Data(repeating: 0x41, count: 128)
        #expect(throws: PeaksFileError.self) { try PeaksFile.decode(junk) }
    }

    @Test("Un file troncato viene rifiutato invece di leggere fuori dai bordi")
    func rejectsTruncatedFile() {
        let full = PeaksFile.encode(makePeaks())
        let cut = full.prefix(full.count / 2)
        #expect(throws: PeaksFileError.self) { try PeaksFile.decode(Data(cut)) }
    }

    @Test("La dimensione del file resta nell'ordine previsto")
    func fileSizeStaysSmall() {
        // 5:45 a 44,1 kHz: il budget dichiarato è 1–2 MB per traccia.
        let peaks = makePeaks(frameCount: 15_214_500)
        let size = PeaksFile.encode(peaks).count
        #expect(size > 1_000_000)
        #expect(size < 2_100_000)
    }
}
