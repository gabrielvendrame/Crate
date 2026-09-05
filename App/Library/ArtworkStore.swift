import AppKit
import Foundation
import DJKit

/// Salvataggio delle foto delle etichette nella cartella `Artwork/` della libreria.
///
/// Le immagini vengono ridimensionate a 1200 px sul lato lungo e salvate in JPEG: l'etichetta di
/// un vinile serve a riconoscere il disco nella cassa, non a essere stampata, e una foto da
/// telefono a piena risoluzione peserebbe dieci volte tanto senza aggiungere nulla.
enum ArtworkStore {
    private static let maximumSide: CGFloat = 1200
    private static let compressionQuality = 0.85

    enum Failure: LocalizedError {
        case unreadableImage
        case encodingFailed

        var errorDescription: String? {
            switch self {
            case .unreadableImage: "Il file non contiene un'immagine leggibile."
            case .encodingFailed: "Impossibile convertire l'immagine in JPEG."
            }
        }
    }

    static func save(
        image: NSImage,
        trackID: String,
        side: VinylSide,
        paths: LibraryPaths
    ) throws -> String {
        guard let jpeg = jpegData(from: image) else { throw Failure.encodingFailed }
        let filename = paths.artworkFilename(trackID: trackID, side: side, fileExtension: "jpg")
        try jpeg.write(to: paths.artworkURL(filename: filename), options: .atomic)
        return filename
    }

    /// Salva un'immagine già scaricata in memoria — è il caso della copertina presa da Discogs.
    static func save(
        data: Data,
        trackID: String,
        side: VinylSide,
        paths: LibraryPaths
    ) throws -> String {
        guard let image = NSImage(data: data) else { throw Failure.unreadableImage }
        return try save(image: image, trackID: trackID, side: side, paths: paths)
    }

    static func save(
        contentsOf url: URL,
        trackID: String,
        side: VinylSide,
        paths: LibraryPaths
    ) throws -> String {
        guard let image = NSImage(contentsOf: url) else { throw Failure.unreadableImage }
        return try save(image: image, trackID: trackID, side: side, paths: paths)
    }

    /// L'immagine copiata negli appunti, se ce n'è una. Copre il caso della foto scattata col
    /// telefono e incollata via Continuity.
    static func imageFromPasteboard() -> NSImage? {
        let pasteboard = NSPasteboard.general
        if let image = NSImage(pasteboard: pasteboard) { return image }
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
           let first = urls.first {
            return NSImage(contentsOf: first)
        }
        return nil
    }

    static func remove(filename: String, paths: LibraryPaths) {
        try? FileManager.default.removeItem(at: paths.artworkURL(filename: filename))
    }

    private static func jpegData(from image: NSImage) -> Data? {
        guard let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return nil
        }
        let width = CGFloat(source.width)
        let height = CGFloat(source.height)
        let scale = min(1, maximumSide / max(width, height))
        let targetWidth = Int((width * scale).rounded())
        let targetHeight = Int((height * scale).rounded())

        guard let context = CGContext(
            data: nil,
            width: targetWidth,
            height: targetHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))
        guard let resized = context.makeImage() else { return nil }

        let representation = NSBitmapImageRep(cgImage: resized)
        return representation.representation(
            using: .jpeg,
            properties: [.compressionFactor: compressionQuality]
        )
    }
}
