import AVFoundation
import AppKit
import DJKit
import SwiftUI

/// Fotografa l'etichetta del disco dalla fotocamera.
///
/// **Con Continuity l'iPhone compare come un normale `AVCaptureDevice`**, quindi non serve niente
/// di speciale per usarlo: la stessa schermata elenca la webcam del Mac e il telefono, e il
/// telefono è quello che serve davvero — una webcam inquadra male un disco tenuto in mano.
///
/// L'immagine finisce dove finiscono le altre, in `Artwork/`, ridimensionata a 1200 px come quelle
/// trascinate o incollate: l'etichetta serve a riconoscere il disco nella cassa, non a essere
/// stampata.
struct LabelCameraSheet: View {
    /// Il modello dell'app. Riferimento diretto e non `@Environment`: vedi `AppModel.shared`.
    @MainActor private var model: AppModel { .shared }
    @Environment(\.dismiss) private var dismiss

    let track: Track
    let side: VinylSide

    @State private var camera = CameraController()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            preview
            Divider()
            controls
        }
        .frame(width: 640, height: 620)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Fotografa l'etichetta · lato \(side.rawValue)")
                .font(.headline)
            Text(track.displayName)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            Color.black
            switch camera.state {
            case .idle, .starting:
                ProgressView()
            case .running:
                CameraPreview(session: camera.session)
            case .denied:
                message(
                    "Crate non ha il permesso di usare la fotocamera.",
                    detail: "Aprilo in Impostazioni di Sistema → Privacy e sicurezza → Fotocamera."
                )
            case .unavailable:
                message(
                    "Nessuna fotocamera disponibile.",
                    detail: "Collega una webcam, oppure sblocca l'iPhone e tienilo vicino: con Continuity compare qui."
                )
            case .failed(let reason):
                message("La fotocamera non è partita.", detail: reason)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(_ title: String, detail: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "video.slash")
                .font(.title)
            Text(title).font(.callout.weight(.medium))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .foregroundStyle(.white)
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if camera.devices.count > 1 {
                Picker("Fotocamera", selection: Binding(
                    get: { camera.selectedDeviceID },
                    set: { id in Task { await camera.select(deviceID: id) } }
                )) {
                    ForEach(camera.devices, id: \.uniqueID) { device in
                        Text(device.localizedName).tag(device.uniqueID as String?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 240)
            }

            Spacer()

            Button("Annulla") { dismiss() }
                .keyboardShortcut(.cancelAction)

            Button("Scatta") { capture() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(camera.state != .running || isSaving)
        }
        .padding(16)
    }

    @State private var isSaving = false

    private func capture() {
        isSaving = true
        Task {
            defer { isSaving = false }
            guard let paths = model.paths else { return }
            do {
                let data = try await camera.capturePhoto()
                let filename = try ArtworkStore.save(
                    data: data, trackID: track.id, side: side, paths: paths
                )
                var updated = model.trackList.first { $0.id == track.id } ?? track
                switch side {
                case .a: updated.labelImageAFilename = filename
                case .b: updated.labelImageBFilename = filename
                }
                model.save(track: updated)
                dismiss()
            } catch {
                model.transientError = "Lo scatto non è riuscito: \(AppModel.describe(error))"
            }
        }
    }
}

/// L'anteprima dal vivo. `AVCaptureVideoPreviewLayer` e non un `AVCaptureVideoDataOutput` con
/// disegno nostro: è il percorso che il sistema ottimizza, e qui l'immagine serve solo a inquadrare.
private struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        view.wantsLayer = true
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspect
        view.layer = layer
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView.layer as? AVCaptureVideoPreviewLayer)?.session = session
    }
}
