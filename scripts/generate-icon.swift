#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift generate-icon.swift <output-icns-path>\n", stderr)
    exit(1)
}

let outputIcnsPath = CommandLine.arguments[1]
let outputURL = URL(fileURLWithPath: outputIcnsPath)
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("tessera-icon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = tempDir.appendingPathComponent("Tessera.iconset", isDirectory: true)

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempDir) }

func drawRoundedRect(_ ctx: CGContext, rect: CGRect, radius: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path)
}

func renderIcon(pixelSize: Int) -> Data? {
    let width = pixelSize
    let height = pixelSize
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { return nil }

    let s = CGFloat(pixelSize)
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)

    // macOS icon safe-area inset (~9.5% margin)
    let margin = s * 0.092
    let cardRect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let cornerRadius = cardRect.width * 0.225

    // Subtle drop shadow
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.018), blur: s * 0.035, color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42))
    drawRoundedRect(ctx, rect: cardRect, radius: cornerRadius)
    ctx.setFillColor(CGColor(red: 0.07, green: 0.08, blue: 0.14, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // Clip to squircle for internal gradients and tiles
    ctx.saveGState()
    drawRoundedRect(ctx, rect: cardRect, radius: cornerRadius)
    ctx.clip()

    // Background obsidian-indigo gradient
    let bgColors = [
        CGColor(red: 0.08, green: 0.09, blue: 0.17, alpha: 1.0),
        CGColor(red: 0.13, green: 0.14, blue: 0.26, alpha: 1.0),
        CGColor(red: 0.06, green: 0.07, blue: 0.13, alpha: 1.0)
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.5, 1.0]) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: cardRect.minX, y: cardRect.maxY),
            end: CGPoint(x: cardRect.maxX, y: cardRect.minY),
            options: []
        )
    }

    // Soft top-left ambient aura
    let auraColors = [
        CGColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 0.34),
        CGColor(red: 0.39, green: 0.40, blue: 0.95, alpha: 0.0)
    ] as CFArray
    if let aura = CGGradient(colorsSpace: colorSpace, colors: auraColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            aura,
            startCenter: CGPoint(x: cardRect.minX + cardRect.width * 0.25, y: cardRect.maxY - cardRect.height * 0.18),
            startRadius: 0,
            endCenter: CGPoint(x: cardRect.minX + cardRect.width * 0.25, y: cardRect.maxY - cardRect.height * 0.18),
            endRadius: cardRect.width * 0.72,
            options: []
        )
    }

    // Mosaic Grid Layout inside the card (Main Left Pane + Stacked Right Panes)
    let pad = cardRect.width * 0.125
    let gap = cardRect.width * 0.052
    let inner = cardRect.insetBy(dx: pad, dy: pad)
    let leftWidth = (inner.width - gap) * 0.54
    let rightWidth = inner.width - gap - leftWidth
    let rightTileHeight = (inner.height - gap) * 0.5
    let tileRadius = cardRect.width * 0.075

    let leftTile = CGRect(x: inner.minX, y: inner.minY, width: leftWidth, height: inner.height)
    let topRightTile = CGRect(x: inner.minX + leftWidth + gap, y: inner.minY + rightTileHeight + gap, width: rightWidth, height: rightTileHeight)
    let bottomRightTile = CGRect(x: inner.minX + leftWidth + gap, y: inner.minY, width: rightWidth, height: rightTileHeight)

    func paintTile(_ rect: CGRect, startColor: CGColor, endColor: CGColor) {
        ctx.saveGState()
        drawRoundedRect(ctx, rect: rect, radius: tileRadius)
        ctx.clip()
        if let grad = CGGradient(colorsSpace: colorSpace, colors: [startColor, endColor] as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: []
            )
        }
        ctx.restoreGState()

        // Crisp subtle top highlight rim
        drawRoundedRect(ctx, rect: rect.insetBy(dx: s * 0.002, dy: s * 0.002), radius: tileRadius)
        ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.28))
        ctx.setLineWidth(max(1.0, s * 0.005))
        ctx.strokePath()
    }

    // Left hero tile: Indigo -> Violet
    paintTile(
        leftTile,
        startColor: CGColor(red: 0.43, green: 0.44, blue: 0.98, alpha: 1.0),
        endColor: CGColor(red: 0.30, green: 0.25, blue: 0.78, alpha: 1.0)
    )

    // Top-right tile: Emerald -> Teal
    paintTile(
        topRightTile,
        startColor: CGColor(red: 0.12, green: 0.82, blue: 0.62, alpha: 1.0),
        endColor: CGColor(red: 0.05, green: 0.58, blue: 0.56, alpha: 1.0)
    )

    // Bottom-right tile: Amethyst -> Rose
    paintTile(
        bottomRightTile,
        startColor: CGColor(red: 0.72, green: 0.38, blue: 0.98, alpha: 1.0),
        endColor: CGColor(red: 0.90, green: 0.28, blue: 0.60, alpha: 1.0)
    )

    // Draw crisp `>_` terminal chevron & cursor inside the left hero tile
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let strokeW = max(1.5, s * 0.026)
    ctx.setLineWidth(strokeW)

    let cx = leftTile.midX
    let cy = leftTile.midY
    let chevronW = leftTile.width * 0.26
    let chevronH = leftTile.width * 0.28

    // `>` chevron
    ctx.move(to: CGPoint(x: cx - chevronW * 0.95, y: cy + chevronH * 0.55))
    ctx.addLine(to: CGPoint(x: cx - chevronW * 0.15, y: cy))
    ctx.addLine(to: CGPoint(x: cx - chevronW * 0.95, y: cy - chevronH * 0.55))
    ctx.strokePath()

    // `_` prompt underscore
    ctx.move(to: CGPoint(x: cx + chevronW * 0.15, y: cy - chevronH * 0.55))
    ctx.addLine(to: CGPoint(x: cx + chevronW * 0.95, y: cy - chevronH * 0.55))
    ctx.strokePath()
    ctx.restoreGState()

    // Subtle command bars inside the right tiles for terminal identity
    func drawBars(in rect: CGRect, widths: [CGFloat]) {
        let barH = max(1.5, rect.height * 0.11)
        let startX = rect.minX + rect.width * 0.18
        var y = rect.maxY - rect.height * 0.32
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.78))
        for frac in widths {
            let barW = rect.width * 0.64 * frac
            let barRect = CGRect(x: startX, y: y - barH / 2, width: barW, height: barH)
            drawRoundedRect(ctx, rect: barRect, radius: barH / 2)
            ctx.fillPath()
            y -= rect.height * 0.24
        }
    }
    drawBars(in: topRightTile, widths: [0.9, 0.55])
    drawBars(in: bottomRightTile, widths: [0.7, 0.95])

    ctx.restoreGState()

    // Outer glass rim
    drawRoundedRect(ctx, rect: cardRect.insetBy(dx: s * 0.004, dy: s * 0.004), radius: cornerRadius)
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.18))
    ctx.setLineWidth(max(1.0, s * 0.008))
    ctx.strokePath()

    guard let cgImage = ctx.makeImage() else { return nil }
    let rep = NSBitmapImageRep(cgImage: cgImage)
    return rep.representation(using: .png, properties: [:])
}

let specs: [(name: String, pixels: Int)] = [
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

for spec in specs {
    guard let pngData = renderIcon(pixelSize: spec.pixels) else {
        fputs("Failed to render \(spec.name)\n", stderr)
        exit(1)
    }
    try pngData.write(to: iconsetURL.appendingPathComponent(spec.name))
}

try FileManager.default.createDirectory(
    at: outputURL.deletingLastPathComponent(),
    withIntermediateDirectories: true
)

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", outputURL.path]
try process.run()
process.waitUntilExit()

if process.terminationStatus != 0 {
    fputs("iconutil failed with status \(process.terminationStatus)\n", stderr)
    exit(process.terminationStatus)
}

print("Generated icon: \(outputURL.path)")
