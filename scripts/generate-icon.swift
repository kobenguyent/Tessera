#!/usr/bin/env swift
import AppKit
import CoreGraphics
import Foundation

guard CommandLine.arguments.count >= 2 else {
    fputs("Usage: swift generate-icon.swift <output-icns-path> [--preview-png <png-path>]\n", stderr)
    exit(1)
}

let outputIcnsPath = CommandLine.arguments[1]
var previewPngPath: String? = nil
if CommandLine.arguments.count >= 4, CommandLine.arguments[2] == "--preview-png" {
    previewPngPath = CommandLine.arguments[3]
}

let outputURL = URL(fileURLWithPath: outputIcnsPath)
let tempDir = FileManager.default.temporaryDirectory
    .appendingPathComponent("tessera-icon-\(UUID().uuidString)", isDirectory: true)
let iconsetURL = tempDir.appendingPathComponent("Tessera.iconset", isDirectory: true)

try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: tempDir) }

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
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

    // macOS standard icon safe-area inset (~9.6% margin)
    let margin = s * 0.096
    let cardRect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let cornerRadius = cardRect.width * 0.225

    // 1. Soft macOS Dock ambient drop shadow
    ctx.saveGState()
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.015),
        blur: s * 0.030,
        color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.44)
    )
    ctx.addPath(roundedRectPath(cardRect, radius: cornerRadius))
    ctx.setFillColor(CGColor(red: 0.07, green: 0.075, blue: 0.105, alpha: 1.0))
    ctx.fillPath()
    ctx.restoreGState()

    // 2. Clip to macOS squircle
    ctx.saveGState()
    ctx.addPath(roundedRectPath(cardRect, radius: cornerRadius))
    ctx.clip()

    // Deep obsidian-graphite chassis (calm, refined studio lighting)
    let bgColors = [
        CGColor(red: 0.125, green: 0.133, blue: 0.175, alpha: 1.0),
        CGColor(red: 0.078, green: 0.084, blue: 0.116, alpha: 1.0),
        CGColor(red: 0.050, green: 0.055, blue: 0.080, alpha: 1.0)
    ] as CFArray
    if let bgGradient = CGGradient(colorsSpace: colorSpace, colors: bgColors, locations: [0.0, 0.52, 1.0]) {
        ctx.drawLinearGradient(
            bgGradient,
            start: CGPoint(x: cardRect.midX, y: cardRect.maxY),
            end: CGPoint(x: cardRect.midX, y: cardRect.minY),
            options: []
        )
    }

    // Subtle cool-indigo top-left studio reflection
    let sheenColors = [
        CGColor(red: 0.36, green: 0.40, blue: 0.94, alpha: 0.14),
        CGColor(red: 0.36, green: 0.40, blue: 0.94, alpha: 0.0)
    ] as CFArray
    if let sheen = CGGradient(colorsSpace: colorSpace, colors: sheenColors, locations: [0.0, 1.0]) {
        ctx.drawRadialGradient(
            sheen,
            startCenter: CGPoint(x: cardRect.minX + cardRect.width * 0.28, y: cardRect.maxY - cardRect.height * 0.08),
            startRadius: 0,
            endCenter: CGPoint(x: cardRect.minX + cardRect.width * 0.28, y: cardRect.maxY - cardRect.height * 0.08),
            endRadius: cardRect.width * 0.72,
            options: []
        )
    }

    // 3. Concentric Asymmetric 3-Tile Mosaic Grid (Tessera's signature 1-left + 2-right layout)
    let pad = cardRect.width * 0.130
    let gap = cardRect.width * 0.048
    let inner = cardRect.insetBy(dx: pad, dy: pad)
    let leftWidth = (inner.width - gap) * 0.54
    let rightWidth = inner.width - gap - leftWidth
    let rightTileHeight = (inner.height - gap) * 0.5
    // Concentric radius: outerRadius (0.225) - pad (0.130) = 0.095 -> tightened to 0.086 for crisp tile precision
    let tileRadius = cardRect.width * 0.086

    let leftTile = CGRect(x: inner.minX, y: inner.minY, width: leftWidth, height: inner.height)
    let topRightTile = CGRect(x: inner.minX + leftWidth + gap, y: inner.minY + rightTileHeight + gap, width: rightWidth, height: rightTileHeight)
    let bottomRightTile = CGRect(x: inner.minX + leftWidth + gap, y: inner.minY, width: rightWidth, height: rightTileHeight)

    // Helper for machined glass tiles with top-lit specular border gradient
    func paintTile(
        _ rect: CGRect,
        topColor: CGColor,
        bottomColor: CGColor,
        topRimColor: CGColor,
        bottomRimColor: CGColor
    ) {
        // Grounding shadow
        ctx.saveGState()
        ctx.setShadow(
            offset: CGSize(width: 0, height: -s * 0.009),
            blur: s * 0.020,
            color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42)
        )
        ctx.addPath(roundedRectPath(rect, radius: tileRadius))
        ctx.setFillColor(bottomColor)
        ctx.fillPath()
        ctx.restoreGState()

        // Main tile body gradient
        ctx.saveGState()
        ctx.addPath(roundedRectPath(rect, radius: tileRadius))
        ctx.clip()
        if let grad = CGGradient(colorsSpace: colorSpace, colors: [topColor, bottomColor] as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                grad,
                start: CGPoint(x: rect.minX, y: rect.maxY),
                end: CGPoint(x: rect.maxX, y: rect.minY),
                options: []
            )
        }
        ctx.restoreGState()

        // Top-lit specular rim (strokes path as mask with vertical gradient)
        let lw = max(1.0, s * 0.0065)
        let strokeRect = rect.insetBy(dx: lw * 0.5, dy: lw * 0.5)
        let strokePath = roundedRectPath(strokeRect, radius: max(1, tileRadius - lw * 0.5))
        ctx.saveGState()
        ctx.addPath(strokePath)
        ctx.setLineWidth(lw)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        if let rimGrad = CGGradient(colorsSpace: colorSpace, colors: [topRimColor, bottomRimColor] as CFArray, locations: [0.0, 1.0]) {
            ctx.drawLinearGradient(
                rimGrad,
                start: CGPoint(x: rect.midX, y: rect.maxY),
                end: CGPoint(x: rect.midX, y: rect.minY),
                options: []
            )
        }
        ctx.restoreGState()
    }

    // Hero Left Tile: Rich, authoritative sapphire-indigo
    paintTile(
        leftTile,
        topColor: CGColor(red: 0.365, green: 0.395, blue: 0.945, alpha: 1.0),
        bottomColor: CGColor(red: 0.235, green: 0.255, blue: 0.745, alpha: 1.0),
        topRimColor: CGColor(red: 0.84, green: 0.87, blue: 1.0, alpha: 0.55),
        bottomRimColor: CGColor(red: 0.50, green: 0.54, blue: 1.0, alpha: 0.14)
    )

    // Top-Right Tile: Machined slate glass
    paintTile(
        topRightTile,
        topColor: CGColor(red: 0.215, green: 0.232, blue: 0.305, alpha: 1.0),
        bottomColor: CGColor(red: 0.145, green: 0.158, blue: 0.218, alpha: 1.0),
        topRimColor: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.24),
        bottomRimColor: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.04)
    )

    // Bottom-Right Tile: Subtle deeper slate glass for quiet architectural rhythm
    paintTile(
        bottomRightTile,
        topColor: CGColor(red: 0.175, green: 0.190, blue: 0.255, alpha: 1.0),
        bottomColor: CGColor(red: 0.120, green: 0.132, blue: 0.185, alpha: 1.0),
        topRimColor: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.20),
        bottomRimColor: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.03)
    )

    // 4. Clean, unmistakable terminal prompt `>_` inside the Hero Left Tile
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.96))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    let strokeW = max(1.6, s * 0.030)
    ctx.setLineWidth(strokeW)

    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.007),
        blur: s * 0.015,
        color: CGColor(red: 0.07, green: 0.08, blue: 0.28, alpha: 0.42)
    )

    let cx = leftTile.midX
    let cy = leftTile.midY
    let unit = leftTile.width * 0.235

    // `>` chevron
    ctx.move(to: CGPoint(x: cx - unit * 0.96, y: cy + unit * 0.62))
    ctx.addLine(to: CGPoint(x: cx - unit * 0.14, y: cy + unit * 0.02))
    ctx.addLine(to: CGPoint(x: cx - unit * 0.96, y: cy - unit * 0.58))
    ctx.strokePath()

    // `_` cursor bar
    ctx.move(to: CGPoint(x: cx + unit * 0.18, y: cy - unit * 0.58))
    ctx.addLine(to: CGPoint(x: cx + unit * 0.98, y: cy - unit * 0.58))
    ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState() // end squircle clip

    // 5. Top-lit outer macOS squircle bezel highlight
    let rimW = max(1.0, s * 0.0075)
    let outerStrokeRect = cardRect.insetBy(dx: rimW * 0.5, dy: rimW * 0.5)
    let outerStrokePath = roundedRectPath(outerStrokeRect, radius: cornerRadius - rimW * 0.5)
    ctx.saveGState()
    ctx.addPath(outerStrokePath)
    ctx.setLineWidth(rimW)
    ctx.replacePathWithStrokedPath()
    ctx.clip()
    if let outerRimGrad = CGGradient(
        colorsSpace: colorSpace,
        colors: [
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.24),
            CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.05)
        ] as CFArray,
        locations: [0.0, 1.0]
    ) {
        ctx.drawLinearGradient(
            outerRimGrad,
            start: CGPoint(x: cardRect.midX, y: cardRect.maxY),
            end: CGPoint(x: cardRect.midX, y: cardRect.minY),
            options: []
        )
    }
    ctx.restoreGState()

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
    if spec.pixels == 1024, let previewPngPath {
        try pngData.write(to: URL(fileURLWithPath: previewPngPath))
    }
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
