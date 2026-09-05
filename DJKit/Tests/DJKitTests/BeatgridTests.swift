import Foundation
import Testing
@testable import DJKit

@Suite("Griglia delle battute")
struct BeatgridTests {

    @Test("Un BPM non valido non produce una griglia")
    func rejectsInvalidTempo() {
        #expect(Beatgrid(bpm: 0, offsetSeconds: 0) == nil)
        #expect(Beatgrid(bpm: -128, offsetSeconds: 0) == nil)
        #expect(Beatgrid(bpm: .nan, offsetSeconds: 0) == nil)
        #expect(Beatgrid(bpm: 120, offsetSeconds: .infinity) == nil)
    }

    @Test("Battute e misure durano quanto devono")
    func durations() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 0))
        #expect(abs(grid.beatDuration - 0.5) < 1e-12)
        #expect(abs(grid.barDuration - 2) < 1e-12)
    }

    @Test("La griglia si estende anche prima del primo downbeat")
    func extendsBackwards() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 1))
        #expect(abs(grid.beatPosition(atSeconds: 1) - 0) < 1e-12)
        #expect(abs(grid.beatPosition(atSeconds: 2) - 2) < 1e-12)
        #expect(abs(grid.beatPosition(atSeconds: 0) - (-2)) < 1e-12)
        #expect(abs(grid.seconds(ofBeat: -4) - (-1)) < 1e-12)
    }

    @Test("L'uno della misura si riconosce anche all'indietro")
    func downbeatsBothWays() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 1))
        #expect(grid.isDownbeat(beat: 0))
        #expect(grid.isDownbeat(beat: 4))
        #expect(grid.isDownbeat(beat: -4))
        #expect(!grid.isDownbeat(beat: -3))
        #expect(!grid.isDownbeat(beat: 2))
    }

    @Test("Il quantize aggancia alla battuta più vicina")
    func snapsToNearestBeat() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 0.25))
        // Battute a 0,25 · 0,75 · 1,25 · 1,75…
        #expect(abs(grid.snap(0.80) - 0.75) < 1e-9)
        #expect(abs(grid.snap(1.10) - 1.25) < 1e-9)
        #expect(abs(grid.snap(0.25) - 0.25) < 1e-9)
    }

    @Test("A mezza battuta l'aggancio è due volte più fine")
    func snapsToHalfBeat() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 0.25))
        #expect(abs(grid.snap(0.55, resolution: .halfBeat) - 0.5) < 1e-9)
        // Lo stesso punto, a battuta intera, va invece sul quarto.
        #expect(abs(grid.snap(0.55, resolution: .beat) - 0.75) < 1e-9)
    }

    @Test("L'aggancio non manda un cue a tempo negativo")
    func snapStaysInsideTheTrack() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 0.4))
        // 0,05 s è più vicino a −0,1 che a 0,4, ma prima dell'inizio non c'è traccia.
        #expect(abs(grid.snap(0.05) - 0.4) < 1e-9)
        #expect(grid.snap(0) >= 0)
    }

    @Test("Trascinando la griglia l'offset resta dentro la prima misura")
    func shiftFoldsIntoTheFirstBar() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 1.5))
        let forward = grid.shifted(bySeconds: 10)
        #expect(forward.offsetSeconds >= 0)
        #expect(forward.offsetSeconds < forward.barDuration)
        // Spostare di cinque misure esatte lascia la griglia dov'era.
        #expect(abs(forward.offsetSeconds - 1.5) < 1e-9)

        let backward = grid.shifted(bySeconds: -2.0)
        #expect(backward.offsetSeconds >= 0)
        #expect(abs(backward.offsetSeconds - 1.5) < 1e-9)
    }

    @Test("Il downbeat si può portare su un punto scelto a mano")
    func alignsDownbeat() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 0))
        let moved = grid.alignedDownbeat(toSeconds: 9.3)
        // 9,3 sta a quattro misure e 1,3 s dall'inizio: resta 1,3.
        #expect(abs(moved.offsetSeconds - 1.3) < 1e-9)
        #expect(abs(moved.beatPosition(atSeconds: 9.3).rounded() - moved.beatPosition(atSeconds: 9.3)) < 1e-9)
    }

    @Test("Le due risoluzioni si scrivono come sui CDJ")
    func resolutionLabels() {
        #expect(QuantizeResolution.beat.label == "1/1")
        #expect(QuantizeResolution.halfBeat.label == "1/2")
        #expect(QuantizeResolution.allCases.count == 2)
    }
}
