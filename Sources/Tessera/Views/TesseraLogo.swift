import AppKit
import CoreGraphics
import SwiftUI

/// Renders the official Tessera macOS app icon (obsidian squircle + 3-tile mosaic + crisp `>_` mark).
/// Used both at runtime for the Dock icon (`NSApplication.shared.applicationIconImage` when running
/// via `swift run`) and inside SwiftUI chrome (`TesseraLogoView`).
enum TesseraAppIconRenderer {
    static func makeCGImage(pixelSize: Int, includeOuterMargin: Bool = true) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        let s = CGFloat(pixelSize)
        ctx.setAllowsAntialiasing(true)
        ctx.setShouldAntialias(true)

        let margin = includeOuterMargin ? s * 0.096 : 0
        let cardRect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
        let cornerRadius = cardRect.width * 0.225

        func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
            CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
        }

        // 1. Soft macOS Dock ambient drop shadow
        if includeOuterMargin {
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
        }

        // 2. Clip to macOS squircle
        ctx.saveGState()
        ctx.addPath(roundedRectPath(cardRect, radius: cornerRadius))
        ctx.clip()

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

        // 3. Concentric Asymmetric 3-Tile Mosaic Grid
        let pad = cardRect.width * 0.130
        let gap = cardRect.width * 0.048
        let inner = cardRect.insetBy(dx: pad, dy: pad)
        let leftWidth = (inner.width - gap) * 0.54
        let rightWidth = inner.width - gap - leftWidth
        let rightTileHeight = (inner.height - gap) * 0.5
        let tileRadius = cardRect.width * 0.086

        let leftTile = CGRect(x: inner.minX, y: inner.minY, width: leftWidth, height: inner.height)
        let topRightTile = CGRect(x: inner.minX + leftWidth + gap, y: inner.minY + rightTileHeight + gap, width: rightWidth, height: rightTileHeight)
        let bottomRightTile = CGRect(x: inner.minX + leftWidth + gap, y: inner.minY, width: rightWidth, height: rightTileHeight)

        func paintTile(
            _ rect: CGRect,
            topColor: CGColor,
            bottomColor: CGColor,
            topRimColor: CGColor,
            bottomRimColor: CGColor
        ) {
            ctx.saveGState()
            ctx.setShadow(
                offset: CGSize(width: 0, height: -cardRect.width * 0.011),
                blur: cardRect.width * 0.025,
                color: CGColor(red: 0, green: 0, blue: 0, alpha: 0.42)
            )
            ctx.addPath(roundedRectPath(rect, radius: tileRadius))
            ctx.setFillColor(bottomColor)
            ctx.fillPath()
            ctx.restoreGState()

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

            let lw = max(1.0, cardRect.width * 0.008)
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

        paintTile(
            leftTile,
            topColor: CGColor(red: 0.365, green: 0.395, blue: 0.945, alpha: 1.0),
            bottomColor: CGColor(red: 0.235, green: 0.255, blue: 0.745, alpha: 1.0),
            topRimColor: CGColor(red: 0.84, green: 0.87, blue: 1.0, alpha: 0.55),
            bottomRimColor: CGColor(red: 0.50, green: 0.54, blue: 1.0, alpha: 0.14)
        )

        paintTile(
            topRightTile,
            topColor: CGColor(red: 0.215, green: 0.232, blue: 0.305, alpha: 1.0),
            bottomColor: CGColor(red: 0.145, green: 0.158, blue: 0.218, alpha: 1.0),
            topRimColor: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.24),
            bottomRimColor: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.04)
        )

        paintTile(
            bottomRightTile,
            topColor: CGColor(red: 0.175, green: 0.190, blue: 0.255, alpha: 1.0),
            bottomColor: CGColor(red: 0.120, green: 0.132, blue: 0.185, alpha: 1.0),
            topRimColor: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.20),
            bottomRimColor: CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.03)
        )

        // 4. Clean `>_` terminal mark inside Hero Left Tile
        ctx.saveGState()
        ctx.setStrokeColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 0.96))
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        let strokeW = max(1.4, cardRect.width * 0.037)
        ctx.setLineWidth(strokeW)

        ctx.setShadow(
            offset: CGSize(width: 0, height: -cardRect.width * 0.008),
            blur: cardRect.width * 0.018,
            color: CGColor(red: 0.07, green: 0.08, blue: 0.28, alpha: 0.42)
        )

        let cx = leftTile.midX
        let cy = leftTile.midY
        let unit = leftTile.width * 0.235

        ctx.move(to: CGPoint(x: cx - unit * 0.96, y: cy + unit * 0.62))
        ctx.addLine(to: CGPoint(x: cx - unit * 0.14, y: cy + unit * 0.02))
        ctx.addLine(to: CGPoint(x: cx - unit * 0.96, y: cy - unit * 0.58))
        ctx.strokePath()

        ctx.move(to: CGPoint(x: cx + unit * 0.18, y: cy - unit * 0.58))
        ctx.addLine(to: CGPoint(x: cx + unit * 0.98, y: cy - unit * 0.58))
        ctx.strokePath()
        ctx.restoreGState()

        ctx.restoreGState() // end squircle clip

        // 5. Top-lit outer bezel highlight
        let rimW = max(1.0, cardRect.width * 0.009)
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

        return ctx.makeImage()
    }

    static func makeNSImage(pixelSize: Int = 512, includeOuterMargin: Bool = true) -> NSImage? {
        guard let cgImage = makeCGImage(pixelSize: pixelSize, includeOuterMargin: includeOuterMargin) else {
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: NSSize(width: pixelSize, height: pixelSize))
        return image
    }
}

/// Crisp SwiftUI badge displaying the official Tessera logo mark.
struct TesseraLogoView: View {
    var size: CGFloat = 28

    private static let cachedMark: NSImage? = TesseraAppIconRenderer.makeNSImage(
        pixelSize: 128,
        includeOuterMargin: false
    )

    var body: some View {
        if let image = Self.cachedMark {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .frame(width: size, height: size)
        } else {
            Image(systemName: "square.grid.2x2.fill")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(Color(hex: "#6366F1"))
                .frame(width: size, height: size)
        }
    }
}
