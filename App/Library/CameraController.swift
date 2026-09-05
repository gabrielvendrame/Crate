import AVFoundation
import Foundation
import Observation

/// Pilota la fotocamera per lo scatto dell'etichetta.
///
/// Sta in una classe sua e non nella vista perché una `AVCaptureSession` ha un ciclo di vita
/// lungo — permessi, avvio, cambio di device, arresto — che non si incastra con la creazione e
/// distruzione continue di una `View`.
///
/// **La sessione si avvia e si ferma fuori dal main thread.** `startRunning()` blocca finché il
/// device non è pronto, che con una fotocamera Continuity vuol dire anche un secondo intero: sul
/// main sarebbe la finestra che si pianta appena si apre il foglio.
@MainActor
@Observable
final class CameraController {
    enum State: Equatable {
        case idle
        case starting
        case running
        case denied
        case unavailable
        case failed(String)
    }

    private(set) var state: State = .idle
    private(set) var devices: [AVCaptureDevice] = []
    private(set) var selectedDeviceID: String?

    /// `AVCaptureSession` non è `Sendable` ma è progettata per essere usata da **una coda alla
    /// volta**, che è il contratto rispettato qui: la configurazione e l'avvio passano da `queue`,
    /// e il resto sta sul main actor. `nonisolated(unsafe)` è la dichiarazione onesta di questo
    /// contratto — la vista dell'anteprima ha bisogno della sessione senza attraversare un `await`.
    nonisolated(unsafe) let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "com.gabrielvendrame.crate.camera")
    private var input: AVCaptureDeviceInput?
    /// Tenuto vivo qui: `capturePhoto` non trattiene il suo delegato, e senza un riferimento
    /// forte lo scatto non arriverebbe mai.
    private var captureDelegate: PhotoCaptureDelegate?

    // MARK: - Avvio

    func start() async {
        guard state == .idle else { return }
        state = .starting

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            guard await AVCaptureDevice.requestAccess(for: .video) else {
                state = .denied
                return
            }
        default:
            state = .denied
            return
        }

        refreshDevices()
        guard let device = devices.first else {
            state = .unavailable
            return
        }
        await configure(device: device)
    }

    /// Webcam interna, webcam USB e **iPhone via Continuity**, che sul Mac è un device come gli
    /// altri: non serve niente di speciale, basta chiederlo nell'elenco.
    private func refreshDevices() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
            mediaType: .video,
            position: .unspecified
        )
        devices = discovery.devices
        // Il telefono per primo: inquadra un disco tenuto in mano molto meglio di una webcam
        // incastrata sopra lo schermo.
        devices.sort { first, second in
            (first.deviceType == .continuityCamera ? 0 : 1) < (second.deviceType == .continuityCamera ? 0 : 1)
        }
    }

    func select(deviceID: String?) async {
        guard let deviceID, deviceID != selectedDeviceID,
              let device = devices.first(where: { $0.uniqueID == deviceID })
        else { return }
        await configure(device: device)
    }

    private func configure(device: AVCaptureDevice) async {
        let newInput: AVCaptureDeviceInput
        do {
            newInput = try AVCaptureDeviceInput(device: device)
        } catch {
            state = .failed(error.localizedDescription)
            return
        }

        let session = self.session
        let output = self.photoOutput
        let previous = self.input
        let box = CaptureBox(session: session, output: output, newInput: newInput, oldInput: previous)

        let succeeded = await withCheckedContinuation { continuation in
            queue.async {
                let box = box
                box.session.beginConfiguration()
                box.session.sessionPreset = .photo
                if let oldInput = box.oldInput { box.session.removeInput(oldInput) }
                guard box.session.canAddInput(box.newInput) else {
                    box.session.commitConfiguration()
                    continuation.resume(returning: false)
                    return
                }
                box.session.addInput(box.newInput)
                if !box.session.outputs.contains(box.output), box.session.canAddOutput(box.output) {
                    box.session.addOutput(box.output)
                }
                box.session.commitConfiguration()
                if !box.session.isRunning { box.session.startRunning() }
                continuation.resume(returning: true)
            }
        }

        guard succeeded else {
            state = .failed("Il device non si è potuto collegare alla sessione.")
            return
        }
        input = newInput
        selectedDeviceID = device.uniqueID
        state = .running
    }

    func stop() {
        let box = CaptureBox(session: session, output: photoOutput, newInput: nil, oldInput: nil)
        queue.async {
            if box.session.isRunning { box.session.stopRunning() }
        }
        state = .idle
    }

    // MARK: - Scatto

    enum CaptureError: LocalizedError {
        case notRunning
        case noData

        var errorDescription: String? {
            switch self {
            case .notRunning: "La fotocamera non è in funzione."
            case .noData: "Lo scatto non ha prodotto un'immagine."
            }
        }
    }

    func capturePhoto() async throws -> Data {
        guard state == .running else { throw CaptureError.notRunning }
        let settings = AVCapturePhotoSettings()
        return try await withCheckedThrowingContinuation { continuation in
            let delegate = PhotoCaptureDelegate { result in
                continuation.resume(with: result)
            }
            captureDelegate = delegate
            photoOutput.capturePhoto(with: settings, delegate: delegate)
        }
    }
}

/// Porta la sessione e i suoi pezzi sulla coda della fotocamera.
///
/// I tipi di AVFoundation non sono `Sendable` e non lo saranno: sono pensati per essere usati da
/// **una** coda alla volta, che è il contratto che questa classe rispetta. La scatola rende
/// esplicito il passaggio invece di nasconderlo dietro una cattura implicita.
private struct CaptureBox: @unchecked Sendable {
    let session: AVCaptureSession
    let output: AVCapturePhotoOutput
    let newInput: AVCaptureDeviceInput!
    let oldInput: AVCaptureDeviceInput?
}

/// Trasforma il delegato di `AVCapturePhotoOutput` in un `await`.
private final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: (Result<Data, Error>) -> Void
    /// Il delegato può essere chiamato più volte in alcune configurazioni; una continuazione
    /// ripresa due volte fa cadere il processo.
    private var didFinish = false

    init(completion: @escaping (Result<Data, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        guard !didFinish else { return }
        didFinish = true
        if let error {
            completion(.failure(error))
        } else if let data = photo.fileDataRepresentation() {
            completion(.success(data))
        } else {
            completion(.failure(CameraController.CaptureError.noData))
        }
    }
}
