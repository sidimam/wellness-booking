#!/usr/bin/env swift
// Genera le icone di Wellness Booking: glifo "calendario con spunta" bianco (per i documenti
// Icon Composer .icon) e gli appiconset 1024px (light/dark/tinted) per ogni colore app.
// Uso: swift scripts/make_icons.swift
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath)
let colors: [(String, (CGFloat, CGFloat, CGFloat))] = [
    ("AppIcon",           (0.05, 0.64, 0.65)),   // teal mywellness (default)
    ("AppIcon-blu",       (0.18, 0.44, 0.89)),
    ("AppIcon-verde",     (0.24, 0.62, 0.34)),
    ("AppIcon-arancione", (0.91, 0.35, 0.05)),
    ("AppIcon-viola",     (0.49, 0.30, 0.88)),
    ("AppIcon-rosso",     (0.84, 0.27, 0.25)),
    ("AppIcon-grafite",   (0.35, 0.40, 0.45)),
]

func context(_ size: Int) -> CGContext {
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    return CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func save(_ ctx: CGContext, to url: URL) {
    let img = ctx.makeImage()!
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, img, nil)
    CGImageDestinationFinalize(dest)
}

/// Glifo: calendario (bordo, barra superiore con due anelli, griglia) + spunta grande.
func drawGlyph(_ ctx: CGContext, size s: CGFloat, color: CGColor) {
    ctx.setFillColor(color); ctx.setStrokeColor(color)
    let w = s * 0.62, h = s * 0.58
    let x = (s - w) / 2, y = (s - h) / 2 - s * 0.01
    let body = CGRect(x: x, y: y, width: w, height: h)
    let r = s * 0.075
    // corpo con bordo
    let lw = s * 0.055
    ctx.setLineWidth(lw)
    ctx.addPath(CGPath(roundedRect: body.insetBy(dx: lw/2, dy: lw/2), cornerWidth: r, cornerHeight: r, transform: nil))
    ctx.strokePath()
    // barra superiore piena
    let barH = h * 0.22
    let bar = CGRect(x: x, y: y + h - barH, width: w, height: barH)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: body, cornerWidth: r, cornerHeight: r, transform: nil)); ctx.clip()
    ctx.fill(bar)
    ctx.restoreGState()
    // anelli
    let ringW = s * 0.045, ringH = s * 0.11
    for cx in [x + w * 0.28, x + w * 0.72] {
        let ring = CGRect(x: cx - ringW/2, y: y + h - ringH * 0.55, width: ringW, height: ringH)
        ctx.addPath(CGPath(roundedRect: ring, cornerWidth: ringW/2, cornerHeight: ringW/2, transform: nil))
        ctx.fillPath()
    }
    // spunta
    ctx.setLineWidth(s * 0.07); ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let cx = x + w / 2, cy = y + (h - barH) / 2
    ctx.move(to: CGPoint(x: cx - w * 0.22, y: cy + h * 0.02))
    ctx.addLine(to: CGPoint(x: cx - w * 0.05, y: cy - h * 0.14))
    ctx.addLine(to: CGPoint(x: cx + w * 0.26, y: cy + h * 0.20))
    ctx.strokePath()
}

func gradient(_ ctx: CGContext, size s: CGFloat, rgb: (CGFloat, CGFloat, CGFloat), dark: Bool) {
    let (r, g, b) = rgb
    let top: [CGFloat] = dark ? [r*0.55, g*0.55, b*0.55, 1] : [min(1, r*1.18+0.05), min(1, g*1.18+0.05), min(1, b*1.18+0.05), 1]
    let bot: [CGFloat] = dark ? [r*0.25, g*0.25, b*0.25, 1] : [r*0.80, g*0.80, b*0.80, 1]
    let cs = CGColorSpace(name: CGColorSpace.sRGB)!
    let grad = CGGradient(colorSpace: cs, colorComponents: top + bot, locations: [0, 1], count: 2)!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
}

let S = 1024
let white = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)

// 1) glifo trasparente per Icon Composer
do {
    let ctx = context(S)
    drawGlyph(ctx, size: CGFloat(S), color: white)
    save(ctx, to: root.appendingPathComponent("Design/glyph.png"))
}

// 2) appiconset per ogni colore
for (name, rgb) in colors {
    let dir = root.appendingPathComponent("WellnessBooking/Assets.xcassets/\(name).appiconset")
    // light
    var ctx = context(S); gradient(ctx, size: CGFloat(S), rgb: rgb, dark: false); drawGlyph(ctx, size: CGFloat(S), color: white)
    save(ctx, to: dir.appendingPathComponent("icon_1024.png"))
    // dark
    ctx = context(S); gradient(ctx, size: CGFloat(S), rgb: rgb, dark: true)
    drawGlyph(ctx, size: CGFloat(S), color: CGColor(srgbRed: min(1, rgb.0*1.3+0.25), green: min(1, rgb.1*1.3+0.25), blue: min(1, rgb.2*1.3+0.25), alpha: 1))
    save(ctx, to: dir.appendingPathComponent("icon_1024_dark.png"))
    // tinted (scala di grigi su nero)
    ctx = context(S); ctx.setFillColor(CGColor(gray: 0.08, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
    drawGlyph(ctx, size: CGFloat(S), color: CGColor(gray: 0.85, alpha: 1))
    save(ctx, to: dir.appendingPathComponent("icon_1024_tinted.png"))
    let contents = """
    {
      "images" : [
        { "filename" : "icon_1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
        { "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ], "filename" : "icon_1024_dark.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" },
        { "appearances" : [ { "appearance" : "luminosity", "value" : "tinted" } ], "filename" : "icon_1024_tinted.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" }
      ],
      "info" : { "author" : "xcode", "version" : 1 }
    }
    """
    try! contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)

    // 3) documento Icon Composer (.icon) con livello glass
    let iconDir = root.appendingPathComponent("Icons/\(name).icon")
    try? FileManager.default.createDirectory(at: iconDir.appendingPathComponent("Assets"), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: iconDir.appendingPathComponent("Assets/glyph.png"))
    try! FileManager.default.copyItem(at: root.appendingPathComponent("Design/glyph.png"), to: iconDir.appendingPathComponent("Assets/glyph.png"))
    let doc = """
    {
      "design-generation": 26,
      "fill": {"automatic-gradient": "extended-srgb:\(String(format: "%.5f", rgb.0)),\(String(format: "%.5f", rgb.1)),\(String(format: "%.5f", rgb.2)),1.00000"},
      "groups": [{
        "layers": [{"image-name": "glyph.png", "name": "calendario", "glass": true,
                    "position": {"scale": 0.95, "translation-in-points": [0, 0]}}],
        "shadow": {"kind": "neutral", "opacity": 0.5},
        "translucency": {"enabled": true, "value": 0.6},
        "specular": true, "blend-mode": "normal", "lighting": "individual"
      }],
      "supported-platforms": {"circles": ["watchOS"], "squares": "shared"}
    }
    """
    try! doc.write(to: iconDir.appendingPathComponent("icon.json"), atomically: true, encoding: .utf8)
    print("icona", name)
}

// Watch appiconset (solo default, 1024 senza alpha)
do {
    let dir = root.appendingPathComponent("Watch/Assets.xcassets/AppIcon.appiconset")
    let ctx = context(S); gradient(ctx, size: CGFloat(S), rgb: colors[0].1, dark: false); drawGlyph(ctx, size: CGFloat(S), color: white)
    save(ctx, to: dir.appendingPathComponent("icon_1024.png"))
    let contents = """
    { "images" : [ { "filename" : "icon_1024.png", "idiom" : "universal", "platform" : "watchos", "size" : "1024x1024" } ],
      "info" : { "author" : "xcode", "version" : 1 } }
    """
    try! contents.write(to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
print("fatto")
