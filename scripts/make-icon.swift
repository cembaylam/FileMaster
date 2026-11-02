// Renders the app icon (source of truth: this file) into an .iconset and compiles Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift [--preview out.png]
//
// Design: Apple macOS icon grid (824pt squircle body on a 1024 canvas). Blue→indigo gradient squircle,
// a white glass folder whose front shows the app's 1:4:3 three-column layout, a highlighted cursor row in
// the middle column, and a play triangle in the preview column (built-in viewer/player).

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

/// Apple-style continuous-corner squircle: superellipse |x|^n + |y|^n = 1.
func squircle(center: CGPoint, half: CGFloat, n: CGFloat = 5) -> CGPath {
    let p = CGMutablePath()
    let steps = 720
    for k in 0..<steps {
        let t = CGFloat(k) / CGFloat(steps) * 2 * .pi
        let c = cos(t), s = sin(t)
        let x = center.x + half * copysign(pow(abs(c), 2 / n), c)
        let y = center.y + half * copysign(pow(abs(s), 2 / n), s)
        k == 0 ? p.move(to: CGPoint(x: x, y: y)) : p.addLine(to: CGPoint(x: x, y: y))
    }
    p.closeSubpath()
    return p
}

func rounded(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func linear(_ ctx: CGContext, _ path: CGPath, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    ctx.restoreGState()
}

func draw(_ ctx: CGContext) {
    let center = CGPoint(x: canvas / 2, y: canvas / 2)
    let body = squircle(center: center, half: 412)

    // Drop shadow under the body.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.32))
    ctx.addPath(body)
    ctx.setFillColor(rgb(0x3B3FD0))
    ctx.fillPath()
    ctx.restoreGState()

    // Background gradient + soft top glow.
    linear(ctx, body, [rgb(0x6AA2FF), rgb(0x4B6BF5), rgb(0x3A2FBF)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    ctx.saveGState()
    ctx.addPath(body)
    ctx.clip()
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [rgb(0xFFFFFF, 0.28), rgb(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 960), startRadius: 0,
                           endCenter: CGPoint(x: 512, y: 960), endRadius: 560, options: [])
    ctx.restoreGState()

    // Hairline inner rim.
    ctx.saveGState()
    ctx.addPath(body)
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.18))
    ctx.setLineWidth(3)
    ctx.strokePath()
    ctx.restoreGState()

    // Folder back (with tab).
    let back = CGMutablePath()
    back.addPath(rounded(CGRect(x: 222, y: 300, width: 580, height: 400), 46))
    back.addPath(rounded(CGRect(x: 222, y: 640, width: 236, height: 96), 38))
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 18, color: rgb(0x10125A, 0.25))
    ctx.addPath(back)
    ctx.setFillColor(rgb(0xDCE6FF, 0.72))
    ctx.fillPath()
    ctx.restoreGState()

    // Folder front panel.
    let front = rounded(CGRect(x: 222, y: 236, width: 580, height: 400), 46)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 26, color: rgb(0x10125A, 0.35))
    ctx.addPath(front)
    ctx.setFillColor(rgb(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()
    linear(ctx, front, [rgb(0xFFFFFF), rgb(0xEEF2FF)], from: CGPoint(x: 512, y: 636), to: CGPoint(x: 512, y: 236))

    // Three columns at 1:4:3 inside the front panel.
    let inner = CGRect(x: 266, y: 280, width: 492, height: 312)
    let unit = inner.width / 8
    let d1 = inner.minX + unit, d2 = inner.minX + unit * 5
    ctx.setFillColor(rgb(0x3A2FBF, 0.14))
    for x in [d1, d2] { ctx.fill(CGRect(x: x - 2, y: inner.minY, width: 4, height: inner.height)) }

    // List rows (faint) in parent + current columns.
    let rowH: CGFloat = 18
    let rowsY: [CGFloat] = [548, 498, 398, 348, 298]
    ctx.setFillColor(rgb(0x3A2FBF, 0.13))
    for (i, y) in rowsY.enumerated() {
        ctx.addPath(rounded(CGRect(x: inner.minX + 12, y: y, width: unit - 26, height: rowH), rowH / 2))
        let w = (unit * 4 - 40) * [0.82, 0.64, 0.74, 0.56, 0.7][i]
        ctx.addPath(rounded(CGRect(x: d1 + 20, y: y, width: w, height: rowH), rowH / 2))
    }
    ctx.fillPath()

    // Cursor row (accent) in the current column.
    let cursor = rounded(CGRect(x: d1 + 14, y: 436, width: unit * 4 - 28, height: 40), 20)
    linear(ctx, cursor, [rgb(0x5E93FF), rgb(0x3D45D8)], from: CGPoint(x: d1, y: 0), to: CGPoint(x: d2, y: 0))

    // Play triangle in the preview column.
    let pc = CGPoint(x: (d2 + inner.maxX) / 2 + 4, y: inner.midY)
    let r: CGFloat = 44
    let tri = CGMutablePath()
    tri.move(to: CGPoint(x: pc.x - r * 0.62, y: pc.y + r))
    tri.addLine(to: CGPoint(x: pc.x + r * 0.95, y: pc.y))
    tri.addLine(to: CGPoint(x: pc.x - r * 0.62, y: pc.y - r))
    tri.closeSubpath()
    let triRounded = tri.copy(strokingWithWidth: 14, lineCap: .round, lineJoin: .round, miterLimit: 1)
    let triShape = CGMutablePath()
    triShape.addPath(tri)
    triShape.addPath(triRounded)
    linear(ctx, triShape, [rgb(0x5E93FF), rgb(0x3D45D8)], from: CGPoint(x: 0, y: pc.y + r), to: CGPoint(x: 0, y: pc.y - r))
}

func render(size: Int) -> CGImage {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setShouldAntialias(true)
    ctx.scaleBy(x: CGFloat(size) / canvas, y: CGFloat(size) / canvas)
    draw(ctx)
    return ctx.makeImage()!
}

func writePNG(_ image: CGImage, _ url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let args = CommandLine.arguments
if let i = args.firstIndex(of: "--preview"), i + 1 < args.count {
    writePNG(render(size: 1024), URL(fileURLWithPath: args[i + 1]))
    exit(0)
}

let iconset = FileManager.default.temporaryDirectory.appendingPathComponent("AppIcon-\(getpid()).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for base in [16, 32, 128, 256, 512] {
    writePNG(render(size: base), iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    writePNG(render(size: base * 2), iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
let out = root.appendingPathComponent("Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.path]
try p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(p.terminationStatus == 0 ? "wrote \(out.path)" : "iconutil failed")
