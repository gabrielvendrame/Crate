// Disegna l'icona dell'app e ne scrive tutte le misure dentro l'asset catalog.
//
//   swift Scripts/make-app-icon.swift
//
// **L'icona è generata da questo file, non è un PNG arrivato da chissà dove.** È il modo di
// tenerla nel tempo: il disegno sta nel repository come codice, si rigenera identica su qualsiasi
// macchina, e correggerla vuol dire cambiare due righe qui invece di riaprire un editor grafico e
// riesportare undici file a mano. I PNG prodotti si versionano comunque, così chi clona compila
// senza dover eseguire nulla.
//
// Il soggetto è un disco visto dall'alto: fondo scuro come l'app, solchi appena accennati,
// etichetta arancione al centro — lo stesso arancione dell'accento — e la traccia di un colpo di
// testina. A 16 pixel restano il cerchio scuro e il punto caldo in mezzo, che è quanto serve per
// riconoscerla nel Dock.

import AppKit
import Foundation

let root = URL(filePath: FileManager.default.currentDirectoryPath)
let iconSet = root.appending(path: "App/Assets.xcassets/AppIcon.appiconset", directoryHint: .isDirectory)
try FileManager.default.createDirectory(at: iconSet, withIntermediateDirectories: true)

// MARK: - Colori

/// Lo stesso arancione dell'accento dell'app, e lo stesso quasi-nero dello sfondo delle waveform.
let labelColor = NSColor(srgbRed: 0.85, green: 0.42, blue: 0.16, alpha: 1)
let labelHighlight = NSColor(srgbRed: 0.96, green: 0.62, blue: 0.28, alpha: 1)
let vinyl = NSColor(srgbRed: 0.09, green: 0.09, blue: 0.11, alpha: 1)
let vinylEdge = NSColor(srgbRed: 0.20, green: 0.20, blue: 0.24, alpha: 1)
let backgroundTop = NSColor(srgbRed: 0.24, green: 0.24, blue: 0.28, alpha: 1)
let backgroundBottom = NSColor(srgbRed: 0.11, green: 0.11, blue: 0.13, alpha: 1)

// MARK: - Disegno

func drawIcon(side: CGFloat, into context: CGContext) {
    let rect = CGRect(x: 0, y: 0, width: side, height: side)
    context.saveGState()

    // Il quadrato con gli angoli arrotondati alla maniera di macOS: il raggio è circa un quinto
    // del lato, e l'icona lascia un margine attorno come tutte le altre nel Dock.
    let inset = side * 0.055
    let plate = rect.insetBy(dx: inset, dy: inset)
    let squircle = NSBezierPath(roundedRect: plate, xRadius: plate.width * 0.225, yRadius: plate.width * 0.225)
    context.addPath(squircle.cgPath)
    context.clip()

    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [backgroundTop.cgColor, backgroundBottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.midX, y: plate.maxY),
        end: CGPoint(x: plate.midX, y: plate.minY),
        options: []
    )

    let center = CGPoint(x: plate.midX, y: plate.midY)
    let discRadius = plate.width * 0.355

    // Il disco.
    context.setFillColor(vinyl.cgColor)
    context.fillEllipse(in: CGRect(
        x: center.x - discRadius, y: center.y - discRadius,
        width: discRadius * 2, height: discRadius * 2
    ))
    context.setStrokeColor(vinylEdge.cgColor)
    context.setLineWidth(max(1, side * 0.006))
    context.strokeEllipse(in: CGRect(
        x: center.x - discRadius, y: center.y - discRadius,
        width: discRadius * 2, height: discRadius * 2
    ))

    // I solchi. Spariscono da soli alle misure piccole, dove sarebbero solo sporco: sotto i 64
    // pixel una linea da mezzo pixel diventa una velatura grigia.
    if side >= 64 {
        context.setStrokeColor(vinylEdge.withAlphaComponent(0.55).cgColor)
        context.setLineWidth(max(0.5, side * 0.0035))
        for step in 1...5 {
            let radius = discRadius * (0.52 + CGFloat(step) * 0.085)
            context.strokeEllipse(in: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
        }
    }

    // L'etichetta: è la parte che si vede anche a 16 pixel.
    let labelRadius = discRadius * 0.42
    let labelGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [labelHighlight.cgColor, labelColor.cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.saveGState()
    context.addEllipse(in: CGRect(
        x: center.x - labelRadius, y: center.y - labelRadius,
        width: labelRadius * 2, height: labelRadius * 2
    ))
    context.clip()
    context.drawLinearGradient(
        labelGradient,
        start: CGPoint(x: center.x, y: center.y + labelRadius),
        end: CGPoint(x: center.x, y: center.y - labelRadius),
        options: []
    )
    context.restoreGState()

    // Il foro centrale.
    context.setFillColor(backgroundBottom.cgColor)
    let holeRadius = max(side * 0.008, discRadius * 0.055)
    context.fillEllipse(in: CGRect(
        x: center.x - holeRadius, y: center.y - holeRadius,
        width: holeRadius * 2, height: holeRadius * 2
    ))

    // La testina: una linea chiara che entra da destra e si ferma sul disco. Alle misure piccole
    // sparisce, perché sarebbe un pixel storto sul bordo.
    if side >= 128 {
        context.setStrokeColor(NSColor.white.withAlphaComponent(0.9).cgColor)
        context.setLineWidth(side * 0.022)
        context.setLineCap(.round)
        context.move(to: CGPoint(x: plate.maxX - plate.width * 0.14, y: plate.maxY - plate.height * 0.16))
        context.addLine(to: CGPoint(x: center.x + discRadius * 0.30, y: center.y + discRadius * 0.44))
        context.strokePath()

        context.setFillColor(NSColor.white.cgColor)
        let tipRadius = side * 0.026
        context.fillEllipse(in: CGRect(
            x: center.x + discRadius * 0.30 - tipRadius,
            y: center.y + discRadius * 0.44 - tipRadius,
            width: tipRadius * 2, height: tipRadius * 2
        ))
    }

    context.restoreGState()
}

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo: path.move(to: points[0])
            case .lineTo: path.addLine(to: points[0])
            case .curveTo: path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .closePath: path.closeSubpath()
            @unknown default: break
            }
        }
        return path
    }
}

// MARK: - Scrittura

func writePNG(side: Int, to url: URL) throws {
    guard let context = CGContext(
        data: nil, width: side, height: side,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("contesto non creato") }

    drawIcon(side: CGFloat(side), into: context)
    guard let image = context.makeImage() else { fatalError("immagine non creata") }
    let representation = NSBitmapImageRep(cgImage: image)
    guard let data = representation.representation(using: .png, properties: [:]) else {
        fatalError("PNG non codificato")
    }
    try data.write(to: url)
}

/// Le misure che macOS chiede a un'icona di applicazione, con le due scale.
let entries: [(size: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

var images: [[String: String]] = []
for entry in entries {
    let pixels = entry.size * entry.scale
    let filename = "crate-\(entry.size)x\(entry.size)@\(entry.scale)x.png"
    try writePNG(side: pixels, to: iconSet.appending(path: filename))
    images.append([
        "size": "\(entry.size)x\(entry.size)",
        "idiom": "mac",
        "filename": filename,
        "scale": "\(entry.scale)x",
    ])
}

let contents: [String: Any] = [
    "images": images,
    "info": ["version": 1, "author": "xcode"],
]
let json = try JSONSerialization.data(
    withJSONObject: contents, options: [.prettyPrinted, .sortedKeys]
)
try json.write(to: iconSet.appending(path: "Contents.json"))

print("Scritte \(entries.count) misure in App/Assets.xcassets/AppIcon.appiconset")
