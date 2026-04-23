#!/usr/bin/env swift
// Pure CoreGraphics rabbit icon generator. No AppKit / NSApp needed.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Usage: swift make_icon.swift <output-iconset-dir>
let args = CommandLine.arguments
guard args.count > 1 else { print("Usage: make_icon.swift <output.iconset>"); exit(1) }
let outDir = args[1]
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: CGColorSpaceCreateDeviceRGB(), components: [r, g, b, a])!
}

let bgColor     = rgb(0.35, 0.55, 0.95)
let white       = rgb(1, 1, 1)
let pink        = rgb(1.0, 0.72, 0.80)
let darkGray    = rgb(0.15, 0.15, 0.15)
let blush       = rgb(1.0, 0.60, 0.68, 0.55)
let lightGray   = rgb(0.75, 0.75, 0.78)

func drawRabbit(ctx: CGContext, size: CGFloat) {
    let s = size
    ctx.saveGState()

    // Background rounded rect
    let bgPath = CGMutablePath()
    let bgInset: CGFloat = s * 0.04
    bgPath.addRoundedRect(in: CGRect(x: bgInset, y: bgInset, width: s - bgInset*2, height: s - bgInset*2),
                          cornerWidth: s * 0.22, cornerHeight: s * 0.22)
    ctx.setFillColor(bgColor)
    ctx.addPath(bgPath); ctx.fillPath()

    // Clip to background shape
    ctx.addPath(bgPath); ctx.clip()

    let cx = s * 0.5       // center x
    let headY = s * 0.52   // center of head circle

    // ── Ears ──────────────────────────────────────────────────────────
    let earW: CGFloat = s * 0.14
    let earH: CGFloat = s * 0.32
    let earY: CGFloat = s * 0.10
    let earLX = cx - s * 0.14
    let earRX = cx + s * 0.14 - earW

    func drawEar(x: CGFloat, outer: CGColor, inner: CGColor) {
        // Outer white ear
        let outerRect = CGRect(x: x, y: earY, width: earW, height: earH)
        let op = CGMutablePath(); op.addRoundedRect(in: outerRect,
            cornerWidth: earW * 0.5, cornerHeight: earW * 0.5)
        ctx.setFillColor(outer); ctx.addPath(op); ctx.fillPath()
        // Inner pink
        let iw = earW * 0.55; let ih = earH * 0.65
        let innerRect = CGRect(x: x + (earW - iw)*0.5, y: earY + earH * 0.12, width: iw, height: ih)
        let ip = CGMutablePath(); ip.addRoundedRect(in: innerRect,
            cornerWidth: iw * 0.5, cornerHeight: iw * 0.5)
        ctx.setFillColor(inner); ctx.addPath(ip); ctx.fillPath()
    }
    drawEar(x: earLX, outer: white, inner: pink)
    drawEar(x: earRX, outer: white, inner: pink)

    // ── Head ──────────────────────────────────────────────────────────
    let headR: CGFloat = s * 0.28
    ctx.setFillColor(white)
    ctx.fillEllipse(in: CGRect(x: cx - headR, y: headY - headR, width: headR*2, height: headR*2))

    // ── Eyes ──────────────────────────────────────────────────────────
    let eyeY  = headY + s * 0.03
    let eyeR: CGFloat  = s * 0.046
    let eyeLX = cx - s * 0.105
    let eyeRX = cx + s * 0.105
    for ex in [eyeLX, eyeRX] {
        ctx.setFillColor(darkGray)
        ctx.fillEllipse(in: CGRect(x: ex - eyeR, y: eyeY - eyeR, width: eyeR*2, height: eyeR*2))
        // Shine
        let sr = eyeR * 0.38
        ctx.setFillColor(white)
        ctx.fillEllipse(in: CGRect(x: ex + eyeR*0.25 - sr, y: eyeY + eyeR*0.25 - sr, width: sr*2, height: sr*2))
    }

    // ── Nose ──────────────────────────────────────────────────────────
    let noseY = headY - s * 0.045
    let noseR: CGFloat = s * 0.028
    ctx.setFillColor(pink)
    ctx.fillEllipse(in: CGRect(x: cx - noseR, y: noseY - noseR, width: noseR*2, height: noseR*2))

    // ── Smile ─────────────────────────────────────────────────────────
    let smileY = noseY - s * 0.03
    let smileW: CGFloat = s * 0.10
    let smile = CGMutablePath()
    smile.move(to: CGPoint(x: cx - smileW, y: smileY))
    smile.addCurve(to: CGPoint(x: cx + smileW, y: smileY),
                   control1: CGPoint(x: cx - smileW * 0.4, y: smileY - s * 0.045),
                   control2: CGPoint(x: cx + smileW * 0.4, y: smileY - s * 0.045))
    ctx.setStrokeColor(darkGray)
    ctx.setLineWidth(s * 0.025)
    ctx.setLineCap(.round)
    ctx.addPath(smile); ctx.strokePath()

    // ── Blush ─────────────────────────────────────────────────────────
    let blushW: CGFloat = s * 0.075; let blushH: CGFloat = s * 0.04
    let blushY = eyeY - s * 0.055
    ctx.setFillColor(blush)
    ctx.fillEllipse(in: CGRect(x: cx - s*0.22 - blushW*0.5, y: blushY, width: blushW, height: blushH))
    ctx.fillEllipse(in: CGRect(x: cx + s*0.22 - blushW*0.5, y: blushY, width: blushW, height: blushH))

    // ── Whiskers ──────────────────────────────────────────────────────
    ctx.setStrokeColor(lightGray)
    ctx.setLineWidth(s * 0.012)
    let wLen: CGFloat = s * 0.13
    let wy = noseY + s * 0.002
    for side: CGFloat in [-1, 1] {
        let baseX = cx + side * (noseR + s * 0.01)
        for angle: CGFloat in [-0.15, 0, 0.15] {
            let dx = side * wLen * cos(angle)
            let dy = wLen * sin(angle)
            ctx.move(to: CGPoint(x: baseX, y: wy))
            ctx.addLine(to: CGPoint(x: baseX + dx, y: wy + dy))
            ctx.strokePath()
        }
    }

    ctx.restoreGState()
}

func writePNG(_ ctx: CGContext, size: Int, name: String) {
    guard let img = ctx.makeImage() else { return }
    let path = (outDir as NSString).appendingPathComponent(name)
    let url = URL(fileURLWithPath: path) as CFURL
    guard let dest = CGImageDestinationCreateWithURL(url, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
    print("  wrote \(name)")
}

let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (px, name) in sizes {
    let cs = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: px, height: px,
                              bitsPerComponent: 8, bytesPerRow: 0,
                              space: cs,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    // Flip to top-left origin
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: 1, y: -1)
    drawRabbit(ctx: ctx, size: CGFloat(px))
    writePNG(ctx, size: px, name: name)
}
print("Icon set written to \(outDir)")
