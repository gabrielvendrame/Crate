import AVFoundation
import Testing
@testable import DJKit

/// Il grafo non viene mai avviato in questi test: creare i nodi e collegarli non tocca il device,
/// mentre `start()` farebbe suonare la macchina di chi esegue la suite.
@MainActor
@Suite("Grafo audio e crossfader")
struct AudioGraphTests {
    @Test("I nodi dei deck si collegano al mixer principale")
    func buildsGraph() throws {
        let graph = try AudioGraph()
        let deckA = graph.makeDeck()
        let deckB = graph.makeDeck()

        #expect(graph.format.channelCount == 2)
        #expect(graph.format.isInterleaved == false)
        #expect(graph.sampleRate > 0)
        #expect(deckA.sourceNode !== deckB.sourceNode)
        #expect(graph.isRunning == false, "il grafo parte al primo play, non al lancio")
    }

    /// Legge a potenza costante: a metà corsa i due deck stanno entrambi a 0,707, così la somma
    /// non satura quando suonano insieme.
    @Test("Il crossfader distribuisce i due deck a potenza costante")
    func crossfaderLaw() throws {
        let graph = try AudioGraph()
        let deckA = graph.makeDeck()
        let deckB = graph.makeDeck()

        graph.crossfader = 0
        #expect(abs(deckA.mixerNode.outputVolume - 1) < 0.001)
        #expect(abs(deckB.mixerNode.outputVolume - 0) < 0.001)

        graph.crossfader = 1
        #expect(abs(deckA.mixerNode.outputVolume - 0) < 0.001)
        #expect(abs(deckB.mixerNode.outputVolume - 1) < 0.001)

        graph.crossfader = 0.5
        #expect(abs(deckA.mixerNode.outputVolume - 0.7071) < 0.001)
        #expect(abs(deckB.mixerNode.outputVolume - 0.7071) < 0.001)
    }

    @Test("Il gain del deck si moltiplica alla quota del crossfader")
    func gainMultipliesCrossfader() throws {
        let graph = try AudioGraph()
        let deck = graph.makeDeck()

        graph.crossfader = 0
        deck.gain = 0.5
        #expect(abs(deck.mixerNode.outputVolume - 0.5) < 0.001)

        deck.gain = 2
        #expect(deck.gain == 1, "il gain non amplifica oltre l'unità")
    }
}
