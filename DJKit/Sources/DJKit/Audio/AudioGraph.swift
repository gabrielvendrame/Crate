import AVFoundation
import Foundation

/// Il grafo audio dell'app: due deck che confluiscono nel mixer principale e da lì al device.
///
/// ```
/// DeckEngine.sourceNode → mixer del deck (gain × crossfader) → mainMixerNode → output
/// ```
///
/// Un solo device di uscita, per scelta: niente preascolto su cuffia separata. Il grafo parte al
/// primo play e non al lancio, così l'app non tiene occupato il device quando non sta suonando.
@MainActor
public final class AudioGraph {
    public enum GraphError: LocalizedError {
        case unsupportedOutputFormat

        public var errorDescription: String? {
            switch self {
            case .unsupportedOutputFormat:
                "Non riesco a configurare l'uscita audio a due canali."
            }
        }
    }

    /// Formato dei nodi dei deck: float32 non interleaved, due canali, frequenza del device al
    /// momento della creazione.
    ///
    /// Resta **fisso** per tutta la vita del grafo. Se l'utente cambia device, la conversione la
    /// fa il mixer principale: ricalcolare il passo del playhead sulla nuova frequenza sposterebbe
    /// il pitch di tutto ciò che sta suonando.
    public let format: AVAudioFormat

    private let engine = AVAudioEngine()
    private var decks: [DeckEngine] = []
    /// Toccato solo da `init` e `deinit`, e il `deinit` non è isolato: da qui il `nonisolated`.
    nonisolated(unsafe) private var configurationObserver: NSObjectProtocol?

    /// 0 = tutto sul deck A, 1 = tutto sul deck B, 0,5 = entrambi al massimo.
    public var crossfader: Double = 0.5 {
        didSet { applyCrossfader() }
    }

    public init() throws {
        let hardwareRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
        let sampleRate = hardwareRate > 0 ? hardwareRate : 44_100
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)
        else { throw GraphError.unsupportedOutputFormat }
        self.format = format

        // Toccare il mixer principale lo istanzia: senza questo la prima connessione fallisce.
        _ = engine.mainMixerNode
        observeConfigurationChanges()
    }

    deinit {
        if let configurationObserver {
            NotificationCenter.default.removeObserver(configurationObserver)
        }
    }

    public var sampleRate: Double { format.sampleRate }

    /// Crea un deck e lo collega. L'ordine di creazione è l'ordine del crossfader: il primo è A.
    public func makeDeck() -> DeckEngine {
        let deck = DeckEngine(format: format)
        deck.graph = self
        engine.attach(deck.sourceNode)
        engine.attach(deck.mixerNode)
        connect(deck)
        decks.append(deck)
        applyCrossfader()
        return deck
    }

    public func startIfNeeded() throws {
        guard !engine.isRunning else { return }
        engine.prepare()
        try engine.start()
    }

    public func stop() {
        engine.stop()
    }

    public var isRunning: Bool { engine.isRunning }

    // MARK: - Crossfader

    /// Legge a potenza costante: a metà corsa i due deck stanno a 0,707 e la somma non satura.
    private func applyCrossfader() {
        let position = min(max(0, crossfader), 1)
        let angle = position * .pi / 2
        for (index, deck) in decks.enumerated() {
            deck.setCrossfaderGain(index == 0 ? cos(angle) : sin(angle))
        }
    }

    // MARK: - Cambio di configurazione

    private func connect(_ deck: DeckEngine) {
        engine.connect(deck.sourceNode, to: deck.mixerNode, format: format)
        engine.connect(deck.mixerNode, to: engine.mainMixerNode, format: format)
    }

    /// Quando l'utente attacca una scheda audio o cambia device, AVAudioEngine smonta le
    /// connessioni verso l'uscita e si ferma: vanno rifatte, altrimenti l'app resta muta senza
    /// dire niente.
    private func observeConfigurationChanges() {
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.handleConfigurationChange()
            }
        }
    }

    private func handleConfigurationChange() {
        let wasRunning = engine.isRunning
        engine.stop()
        for deck in decks { connect(deck) }
        applyCrossfader()
        guard wasRunning else { return }
        try? startIfNeeded()
    }
}
