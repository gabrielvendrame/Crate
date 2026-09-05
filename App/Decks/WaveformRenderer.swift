import DJKit
import Metal
import MetalKit

/// Disegna la waveform zoomata con Metal.
///
/// Non c'è geometria da ricostruire a ogni frame: la cache dei peaks vive in un buffer sulla GPU e
/// il fragment shader decide colonna per colonna cosa disegnare, quindi far scorrere la waveform
/// costa solo l'aggiornamento di cinque numeri. È ciò che permette di restare a 60 fps quando in
/// M4 la testina si muoverà davvero.
///
/// Il buffer si ricarica solo quando cambia la traccia o il livello di zoom scelto — non a ogni
/// disegno.
final class WaveformRenderer: NSObject, MTKViewDelegate {
    /// Stesso ordine di campi di `WaveformBin` in `Waveform.metal`.
    private struct Bin {
        var minimum: Float
        var maximum: Float
        var low: Float
        var mid: Float
        var high: Float
    }

    /// Stesso ordine di campi di `WaveformUniforms` in `Waveform.metal`.
    private struct Uniforms {
        var startBin: Float
        var binsPerPixel: Float
        var pixelWidth: Float
        var pixelHeight: Float
        var amplitudeScale: Float
        var binCount: UInt32
        var markerCount: UInt32
    }

    /// Quanti marker si caricano al massimo. I memory cue sono illimitati per progetto, ma su una
    /// traccia sola non ce ne stanno cento: il tetto è una rete, non un limite di prodotto.
    private static let maximumMarkers = 128

    /// Frazione della larghezza in cui sta la testina: al centro, come su rekordbox — si vede
    /// tanto di ciò che arriva quanto di ciò che è appena passato.
    private static let playheadFraction = 0.5

    /// La vista da ridisegnare e il display link che la pilota.
    ///
    /// **Il timer interno di `MTKView` non basta**: quando l'utente trascina un controllo AppKit
    /// — uno `Slider`, il divisore di una split view, la barra di scorrimento — il run loop entra
    /// in modalità di tracking, e i timer registrati nella modalità normale smettono di scattare.
    /// Risultato: la waveform si inchioda mentre si muove un fader, che è esattamente quello che
    /// Gabriel ha segnalato. Un `CADisplayLink` aggiunto in `.common` continua a battere anche
    /// durante il tracking.
    private weak var view: MTKView?
    private var displayLink: CADisplayLink?

    private var device: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pipeline: MTLRenderPipelineState?

    private var trackID: String?
    private var peaks: Peaks?
    private var playheadSeconds: Double = 0
    private var visibleSeconds: Double = 8
    /// Quando c'è, è lei a dire dov'è la testina: viene dal motore audio e non dal ciclo di
    /// aggiornamento di SwiftUI, quindi lo scorrimento resta fluido anche a 60 fps.
    private var livePosition: (@Sendable () -> Double)?
    private var markers: [CueMarker] = []

    private var binBuffer: MTLBuffer?
    private var uploadedKey: String?
    private var uploadedBinCount = 0

    private var markerBuffer: MTLBuffer?
    /// Con cosa è stato costruito il buffer dei marker. Le posizioni sono in bin, quindi cambiano
    /// anche solo cambiando livello di zoom: senza il `binSize` nella chiave, i marker
    /// resterebbero dove stavano prima della zoomata.
    private var uploadedMarkers: [CueMarker] = []
    private var uploadedMarkerBinSize = 0
    private var uploadedMarkerCount = 0

    /// `MTKView` espone device e formato dei pixel sul main actor: la chiamata arriva da
    /// `makeNSView`, che è già lì.
    @MainActor
    func configure(view: MTKView) {
        self.view = view
        guard let device = view.device else { return }
        self.device = device
        commandQueue = device.makeCommandQueue()

        guard let library = device.makeDefaultLibrary(),
              let vertexFunction = library.makeFunction(name: "waveformVertex"),
              let fragmentFunction = library.makeFunction(name: "waveformFragment")
        else { return }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
    }

    func update(
        trackID: String?,
        peaks: Peaks?,
        playheadSeconds: Double,
        visibleSeconds: Double,
        markers: [CueMarker] = [],
        livePosition: (@Sendable () -> Double)? = nil
    ) {
        if trackID != self.trackID || peaks == nil {
            binBuffer = nil
            uploadedKey = nil
            uploadedBinCount = 0
        }
        self.trackID = trackID
        self.peaks = peaks
        self.playheadSeconds = playheadSeconds
        self.visibleSeconds = visibleSeconds
        self.markers = markers
        self.livePosition = livePosition
    }

    /// Accende o spegne il battito a 60 fps. Il link si crea alla prima richiesta e resta.
    @MainActor
    func setRunning(_ isRunning: Bool) {
        if displayLink == nil, let view {
            let link = view.displayLink(target: self, selector: #selector(step))
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
        displayLink?.isPaused = !isRunning
    }

    /// `@MainActor` senza rete: un `CADisplayLink` aggiunto a `RunLoop.main` chiama sempre dal
    /// thread principale, quindi il controllo di isolamento non può fallire.
    @MainActor
    @objc
    private func step() {
        // `draw()` disegna subito: la vista sta in modalità su richiesta, quindi il battito del
        // link è l'unica cosa che la fa muovere mentre il deck suona.
        view?.draw()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // Le uniform si ricalcolano a ogni disegno dalla dimensione corrente: niente da fare qui.
    }

    func draw(in view: MTKView) {
        guard let commandQueue,
              let descriptor = view.currentRenderPassDescriptor,
              let drawable = view.currentDrawable,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        if let pipeline, var uniforms = prepare(drawableSize: view.drawableSize),
           let binBuffer, let markerBuffer {
            encoder.setRenderPipelineState(pipeline)
            encoder.setFragmentBuffer(binBuffer, offset: 0, index: 0)
            encoder.setFragmentBytes(&uniforms, length: MemoryLayout<Uniforms>.stride, index: 1)
            encoder.setFragmentBuffer(markerBuffer, offset: 0, index: 2)
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        encoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Preparazione

    private func prepare(drawableSize: CGSize) -> Uniforms? {
        guard let peaks, peaks.frameCount > 0, peaks.sampleRate > 0,
              drawableSize.width >= 1, visibleSeconds > 0
        else { return nil }

        let width = Double(drawableSize.width)
        let framesPerPixel = peaks.sampleRate * visibleSeconds / width
        let level = peaks.level(framesPerPixel: framesPerPixel)
        guard !level.bins.isEmpty else { return nil }

        let key = "\(trackID ?? "")#\(level.binSize)"
        if key != uploadedKey || binBuffer == nil {
            guard let buffer = makeBuffer(level: level) else { return nil }
            binBuffer = buffer
            uploadedKey = key
            uploadedBinCount = level.count
        }

        let binsPerPixel = framesPerPixel / Double(level.binSize)
        let position = livePosition?() ?? playheadSeconds
        let centerBin = position * peaks.sampleRate / Double(level.binSize)
        let startBin = centerBin - width * binsPerPixel * Self.playheadFraction

        prepareMarkers(sampleRate: peaks.sampleRate, binSize: level.binSize)

        return Uniforms(
            startBin: Float(startBin),
            binsPerPixel: Float(binsPerPixel),
            pixelWidth: Float(width),
            pixelHeight: Float(drawableSize.height),
            amplitudeScale: Float(WaveformPalette.amplitudeScale),
            binCount: UInt32(uploadedBinCount),
            markerCount: UInt32(uploadedMarkerCount)
        )
    }

    /// Ricarica il buffer dei marker solo quando cambia qualcosa: la lista dei cue o il livello
    /// di zoom. Ricostruirlo a ogni disegno significherebbe un'allocazione sessanta volte al
    /// secondo per una decina di numeri.
    private func prepareMarkers(sampleRate: Double, binSize: Int) {
        let unchanged = markers == uploadedMarkers
            && binSize == uploadedMarkerBinSize
            && markerBuffer != nil
        guard !unchanged else { return }

        uploadedMarkers = markers
        uploadedMarkerBinSize = binSize

        var packed = markers.prefix(Self.maximumMarkers).map { marker in
            let rgb = marker.rgb
            return SIMD4<Float>(
                Float(marker.seconds * sampleRate / Double(binSize)),
                Float(rgb.x),
                Float(rgb.y),
                Float(rgb.z)
            )
        }
        uploadedMarkerCount = packed.count
        // Metal vuole comunque un buffer allacciato: con zero marker si carica un elemento
        // finto, che il ciclo del fragment shader non guarda perché `markerCount` è 0.
        if packed.isEmpty { packed = [SIMD4<Float>(repeating: 0)] }

        markerBuffer = packed.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return nil }
            return device?.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
    }

    private func makeBuffer(level: PeaksLevel) -> MTLBuffer? {
        guard let device else { return nil }
        var packed = [Bin]()
        packed.reserveCapacity(level.count)
        for bin in level.bins {
            packed.append(
                Bin(
                    minimum: bin.minimum,
                    maximum: bin.maximum,
                    low: bin.low,
                    mid: bin.mid,
                    high: bin.high
                )
            )
        }
        return packed.withUnsafeBytes { raw in
            guard let base = raw.baseAddress, raw.count > 0 else { return nil }
            return device.makeBuffer(bytes: base, length: raw.count, options: .storageModeShared)
        }
    }
}
