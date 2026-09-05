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

    @Test("Il salto di battute sposta di quanto deve, nei due versi")
    func beatJumpMovesByBeats() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 0))
        // Mezzo secondo a battuta: 16 battute sono 8 secondi.
        #expect(abs(grid.seconds(afterJumping: 16, fromSeconds: 10, snappingTo: nil) - 18) < 1e-12)
        #expect(abs(grid.seconds(afterJumping: -16, fromSeconds: 10, snappingTo: nil) - 2) < 1e-12)
        #expect(abs(grid.seconds(afterJumping: 0, fromSeconds: 10, snappingTo: nil) - 10) < 1e-12)
    }

    @Test("Con l'aggancio, saltare da fuori griglia riporta in battuta e ci resta")
    func beatJumpSnapsAndStaysOnGrid() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 0))
        // Si parte 12 ms fuori battuta, come capita saltando mentre la testina gira.
        var position = 10.012
        for _ in 0..<4 {
            position = grid.seconds(afterJumping: 8, fromSeconds: position, snappingTo: .beat)
        }
        // Quattro salti da 8 battute sono 16 secondi, e lo scarto iniziale è sparito al primo.
        #expect(abs(position - 26) < 1e-9)
    }

    @Test("Senza aggancio lo scarto iniziale se lo portano dietro tutti i salti")
    func beatJumpWithoutSnapKeepsTheOffset() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 0))
        var position = 10.012
        for _ in 0..<4 {
            position = grid.seconds(afterJumping: 8, fromSeconds: position, snappingTo: nil)
        }
        #expect(abs(position - 26.012) < 1e-9)
    }

    @Test("A mezza battuta il salto si aggancia anche fra due battute")
    func beatJumpSnapsToHalfBeat() throws {
        let grid = try #require(Beatgrid(bpm: 120, offsetSeconds: 0))
        // Partendo a metà battuta, l'aggancio a 1/2 lascia dov'è invece di tirare sull'uno.
        let jumped = grid.seconds(afterJumping: 8, fromSeconds: 10.25, snappingTo: .halfBeat)
        #expect(abs(jumped - 14.25) < 1e-9)
    }

    @Test("Le quattro taglie del salto contano in battute, non in misure")
    func jumpSizesCountBeats() {
        #expect(BeatJumpSize.allCases.map(\.beats) == [8, 16, 32, 64])
        #expect(BeatJumpSize.sixteen.bars == 4)
        #expect(BeatJumpSize.sixtyFour.bars == 16)
        #expect(BeatJumpSize.eight.label == "8")
    }

    @Test("Le due risoluzioni si scrivono come sui CDJ")
    func resolutionLabels() {
        #expect(QuantizeResolution.beat.label == "1/1")
        #expect(QuantizeResolution.halfBeat.label == "1/2")
        #expect(QuantizeResolution.allCases.count == 2)
    }
}
