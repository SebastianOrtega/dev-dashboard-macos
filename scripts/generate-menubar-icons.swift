import AppKit
import Foundation

let fileManager = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
let root = scriptURL
    .deletingLastPathComponent()
    .deletingLastPathComponent()
let iconSetURL = root
    .appendingPathComponent("menubar-app")
    .appendingPathComponent("Resources")
    .appendingPathComponent("Assets.xcassets")
    .appendingPathComponent("AppIcon.appiconset")

try fileManager.createDirectory(at: iconSetURL, withIntermediateDirectories: true)

let specs: [(filename: String, size: CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

let canvasColor = NSColor(calibratedRed: 0.09, green: 0.14, blue: 0.16, alpha: 1)
let accentA = NSColor(calibratedRed: 0.14, green: 0.72, blue: 0.62, alpha: 1)
let accentB = NSColor(calibratedRed: 0.19, green: 0.48, blue: 0.93, alpha: 1)
let highlight = NSColor(calibratedRed: 0.96, green: 0.98, blue: 0.97, alpha: 1)

func makeImage(size: CGFloat) -> NSImage {
    let pixelSize = Int(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelSize,
        pixelsHigh: pixelSize,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else {
        fatalError("No se pudo crear bitmap para icono")
    }

    bitmap.size = NSSize(width: size, height: size)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }

    guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        fatalError("No se pudo crear contexto para icono")
    }

    NSGraphicsContext.current = context

    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.23

    let backgroundPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    canvasColor.setFill()
    backgroundPath.fill()

    let glowRect = rect.insetBy(dx: size * 0.04, dy: size * 0.04)
    let glowPath = NSBezierPath(roundedRect: glowRect, xRadius: radius * 0.9, yRadius: radius * 0.9)
    let gradient = NSGradient(colors: [
        accentA.withAlphaComponent(0.55),
        accentB.withAlphaComponent(0.25),
        canvasColor.withAlphaComponent(0.15)
    ])!
    gradient.draw(in: glowPath, angle: -35)

    let plateRect = rect.insetBy(dx: size * 0.16, dy: size * 0.16)
    let platePath = NSBezierPath(roundedRect: plateRect, xRadius: size * 0.12, yRadius: size * 0.12)
    NSColor.white.withAlphaComponent(0.08).setFill()
    platePath.fill()

    let topBarRect = NSRect(
        x: plateRect.minX,
        y: plateRect.maxY - size * 0.16,
        width: plateRect.width,
        height: size * 0.12
    )
    let topBarPath = NSBezierPath(roundedRect: topBarRect, xRadius: size * 0.05, yRadius: size * 0.05)
    accentA.withAlphaComponent(0.95).setFill()
    topBarPath.fill()

    let leftCol = NSRect(
        x: plateRect.minX + size * 0.08,
        y: plateRect.minY + size * 0.12,
        width: size * 0.18,
        height: size * 0.26
    )
    let rightCol = NSRect(
        x: leftCol.maxX + size * 0.07,
        y: leftCol.minY,
        width: size * 0.28,
        height: size * 0.18
    )
    let bottomCol = NSRect(
        x: rightCol.minX,
        y: plateRect.minY + size * 0.07,
        width: size * 0.36,
        height: size * 0.08
    )

    for bar in [leftCol, rightCol, bottomCol] {
        let path = NSBezierPath(roundedRect: bar, xRadius: size * 0.03, yRadius: size * 0.03)
        highlight.withAlphaComponent(0.9).setFill()
        path.fill()
    }

    let bolt = NSBezierPath()
    bolt.move(to: NSPoint(x: size * 0.58, y: size * 0.72))
    bolt.line(to: NSPoint(x: size * 0.46, y: size * 0.48))
    bolt.line(to: NSPoint(x: size * 0.58, y: size * 0.48))
    bolt.line(to: NSPoint(x: size * 0.5, y: size * 0.26))
    bolt.line(to: NSPoint(x: size * 0.72, y: size * 0.58))
    bolt.line(to: NSPoint(x: size * 0.58, y: size * 0.58))
    bolt.close()
    accentB.setFill()
    bolt.fill()

    let image = NSImage(size: NSSize(width: size, height: size))
    image.addRepresentation(bitmap)
    return image
}

func writePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiffData = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiffData),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "IconGeneration", code: 1, userInfo: [NSLocalizedDescriptionKey: "No se pudo serializar PNG"])
    }

    try pngData.write(to: url)
}

for spec in specs {
    let image = makeImage(size: spec.size)
    try writePNG(image, to: iconSetURL.appendingPathComponent(spec.filename))
}

print("Generated \(specs.count) app icon PNG files in \(iconSetURL.path)")
