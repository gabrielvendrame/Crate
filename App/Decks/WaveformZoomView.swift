import DJKit
import MetalKit
import SwiftUI

/// La vista ravvicinata della waveform, quella su cui si lavora davvero: scorre in orizzontale
/// con la testina ferma al centro.
///
/// Due modalità, secondo cosa sta succedendo. Mentre il deck suona la vista viene ridisegnata a
/// 60 fps da un `CADisplayLink` e chiede la posizione al motore audio a ogni frame, senza passare
/// da SwiftUI: fare scorrere la waveform costa l'aggiornamento di cinque numeri, ricostruire
/// l'albero delle viste sessanta volte al secondo costerebbe molto di più. Quando è ferma non
/// consuma niente: un disegno solo per ogni scrub o cambio di zoom.
///
/// La vista resta **sempre** in modalità su richiesta (`isPaused = true`): il movimento lo dà il
/// display link, che è registrato in `.common` e quindi continua a battere anche mentre l'utente
/// tiene premuto un controllo AppKit. Il timer interno di `MTKView` invece si fermerebbe.
struct WaveformZoomView: NSViewRepresentable {
    let trackID: String?
    let peaks: Peaks?
    let playheadSeconds: Double
    let visibleSeconds: Double
    /// Hot cue, memory cue e cue di lavoro, disegnati come marker dentro lo shader.
    let markers: [CueMarker]
    /// La griglia delle battute, disegnata anch'essa dallo shader: deve restare inchiodata alla
    /// waveform mentre scorre, e un overlay SwiftUI a 20 Hz striscerebbe visibilmente.
    let beatgrid: Beatgrid?
    /// Il deck sta suonando: la vista si disegna da sé.
    let isRunning: Bool
    /// Sonda della posizione letta a ogni frame, leggibile da qualsiasi thread. `nil` quando non
    /// c'è audio: si ricade su `playheadSeconds`.
    let livePosition: (@Sendable () -> Double)?

    func makeCoordinator() -> WaveformRenderer {
        WaveformRenderer()
    }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: MTLCreateSystemDefaultDevice())
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0.07, green: 0.07, blue: 0.09, alpha: 1)
        view.autoResizeDrawable = true
        view.preferredFramesPerSecond = 60
        view.isPaused = true
        view.enableSetNeedsDisplay = true
        view.delegate = context.coordinator
        context.coordinator.configure(view: view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        context.coordinator.update(
            trackID: trackID,
            peaks: peaks,
            playheadSeconds: playheadSeconds,
            visibleSeconds: visibleSeconds,
            markers: markers,
            beatgrid: beatgrid,
            livePosition: livePosition
        )
        context.coordinator.setRunning(isRunning)
        if !isRunning { nsView.needsDisplay = true }
    }
}
