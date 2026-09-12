// Renders Klapa's app icon at every size the macOS asset catalog wants.
// Run: swift scripts/generate-icon.swift
import AppKit
import CoreGraphics
import Foundation

let sizes = [16, 32, 64, 128, 256, 512, 1024]
let outputDirectory = URL(fileURLWithPath: "Klapa/Resources/Assets.xcassets/AppIcon.appiconset")

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

func draw(size: Int) -> Data? {
    let dimension = CGFloat(size)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    // macOS icons carry their own squircle; the system does not mask for us.
    let inset = dimension * 0.08
    let plate = CGRect(x: inset, y: inset, width: dimension - inset * 2, height: dimension - inset * 2)
    let plateRadius = plate.width * 0.225

    let gradient = CGGradient(
        colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
        colors: [
            CGColor(red: 0.12, green: 0.16, blue: 0.24, alpha: 1),
            CGColor(red: 0.05, green: 0.07, blue: 0.11, alpha: 1),
        ] as CFArray,
        locations: [0, 1]
    )!

    context.saveGState()
    context.addPath(CGPath(roundedRect: plate, cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil))
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: []
    )
    context.restoreGState()

    // The mark: an external monitor lit up, a closed laptop lying beneath it.
    let stroke = max(dimension * 0.045, 1)
    context.setLineJoin(.round)
    context.setLineCap(.round)

    let monitorWidth = plate.width * 0.62
    let monitorHeight = monitorWidth * 0.60
    let monitor = CGRect(
        x: plate.midX - monitorWidth / 2,
        y: plate.midY - monitorHeight * 0.18,
        width: monitorWidth,
        height: monitorHeight
    )

    context.setFillColor(CGColor(red: 0.38, green: 0.78, blue: 0.98, alpha: 0.16))
    context.setStrokeColor(CGColor(red: 0.78, green: 0.90, blue: 1.0, alpha: 1))
    context.setLineWidth(stroke)
    let monitorPath = CGPath(
        roundedRect: monitor,
        cornerWidth: monitor.height * 0.14,
        cornerHeight: monitor.height * 0.14,
        transform: nil
    )
    context.addPath(monitorPath)
    context.drawPath(using: .fillStroke)

    // Monitor stand.
    let standWidth = monitor.width * 0.30
    let stand = CGRect(
        x: monitor.midX - standWidth / 2,
        y: monitor.minY - stroke * 1.6,
        width: standWidth,
        height: stroke * 1.6
    )
    context.setFillColor(CGColor(red: 0.78, green: 0.90, blue: 1.0, alpha: 1))
    context.fill(stand)

    // Closed laptop: a flat slab, the lid shut.
    let laptopWidth = plate.width * 0.50
    let laptop = CGRect(
        x: plate.midX - laptopWidth / 2,
        y: plate.minY + plate.height * 0.13,
        width: laptopWidth,
        height: stroke * 1.5
    )
    context.setFillColor(CGColor(red: 0.55, green: 0.62, blue: 0.72, alpha: 1))
    context.addPath(CGPath(
        roundedRect: laptop,
        cornerWidth: laptop.height / 2,
        cornerHeight: laptop.height / 2,
        transform: nil
    ))
    context.fillPath()

    guard let image = context.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: image)
    rep.size = NSSize(width: dimension, height: dimension)
    return rep.representation(using: .png, properties: [:])
}

for size in sizes {
    guard let data = draw(size: size) else {
        FileHandle.standardError.write("failed at \(size)\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: outputDirectory.appendingPathComponent("icon_\(size).png"))
}

// Asset catalog manifest: macOS wants explicit 1x/2x pairs.
struct Entry: Encodable {
    let size: String
    let idiom = "mac"
    let filename: String
    let scale: String
}

let entries = [
    Entry(size: "16x16", filename: "icon_16.png", scale: "1x"),
    Entry(size: "16x16", filename: "icon_32.png", scale: "2x"),
    Entry(size: "32x32", filename: "icon_32.png", scale: "1x"),
    Entry(size: "32x32", filename: "icon_64.png", scale: "2x"),
    Entry(size: "128x128", filename: "icon_128.png", scale: "1x"),
    Entry(size: "128x128", filename: "icon_256.png", scale: "2x"),
    Entry(size: "256x256", filename: "icon_256.png", scale: "1x"),
    Entry(size: "256x256", filename: "icon_512.png", scale: "2x"),
    Entry(size: "512x512", filename: "icon_512.png", scale: "1x"),
    Entry(size: "512x512", filename: "icon_1024.png", scale: "2x"),
]

struct Manifest: Encodable {
    struct Info: Encodable { let version = 1; let author = "xcode" }
    let images: [Entry]
    let info = Info()
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
try encoder.encode(Manifest(images: entries))
    .write(to: outputDirectory.appendingPathComponent("Contents.json"))

print("icons written to \(outputDirectory.path)")
