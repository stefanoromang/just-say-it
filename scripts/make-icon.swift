// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it
//
// Renders the app icon: a glowing neon waveform on a deep night-blue squircle.

import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let inset = s * 0.09
    let rect = NSRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let shape = NSBezierPath(roundedRect: rect, xRadius: s * 0.22, yRadius: s * 0.22)

    // Background: deep night gradient.
    NSGradient(colors: [NSColor(red: 0.05, green: 0.03, blue: 0.16, alpha: 1),
                        NSColor(red: 0.12, green: 0.02, blue: 0.24, alpha: 1)])!.draw(in: shape, angle: -70)

    // Neon rim.
    let rim = NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.012, dy: s * 0.012), xRadius: s * 0.21, yRadius: s * 0.21)
    rim.lineWidth = s * 0.018
    NSGraphicsContext.current?.saveGraphicsState()
    let rimGlow = NSShadow(); rimGlow.shadowColor = NSColor(red: 0, green: 0.9, blue: 1, alpha: 0.9); rimGlow.shadowBlurRadius = s * 0.04; rimGlow.set()
    NSGradient(colors: [NSColor(red: 0, green: 0.9, blue: 1, alpha: 1), NSColor(red: 1, green: 0.16, blue: 0.62, alpha: 1)])!
        .draw(in: rim.copy() as! NSBezierPath, angle: 0)
    NSColor(red: 0, green: 0.9, blue: 1, alpha: 0.9).setStroke()
    rim.stroke()
    NSGraphicsContext.current?.restoreGraphicsState()
    NSGradient(colors: [NSColor(red: 0.05, green: 0.03, blue: 0.16, alpha: 1),
                        NSColor(red: 0.12, green: 0.02, blue: 0.24, alpha: 1)])!.draw(in: NSBezierPath(roundedRect: rect.insetBy(dx: s * 0.03, dy: s * 0.03), xRadius: s * 0.2, yRadius: s * 0.2), angle: -70)

    // Glowing waveform: cyan → pink → purple → green.
    let neon: [NSColor] = [
        NSColor(red: 0.00, green: 0.90, blue: 1.00, alpha: 1), NSColor(red: 0.00, green: 0.90, blue: 1.00, alpha: 1),
        NSColor(red: 1.00, green: 0.16, blue: 0.62, alpha: 1), NSColor(red: 1.00, green: 0.16, blue: 0.62, alpha: 1),
        NSColor(red: 0.66, green: 0.33, blue: 1.00, alpha: 1), NSColor(red: 0.22, green: 1.00, blue: 0.08, alpha: 1),
        NSColor(red: 0.22, green: 1.00, blue: 0.08, alpha: 1),
    ]
    let bars: [CGFloat] = [0.30, 0.55, 0.82, 0.62, 0.95, 0.58, 0.34]
    let bw = rect.width * 0.072, gap = rect.width * 0.048
    let total = CGFloat(bars.count) * bw + CGFloat(bars.count - 1) * gap
    var x = rect.midX - total / 2
    for (i, b) in bars.enumerated() {
        let h = rect.height * 0.6 * b
        let bar = NSBezierPath(roundedRect: NSRect(x: x, y: rect.midY - h / 2, width: bw, height: h), xRadius: bw / 2, yRadius: bw / 2)
        NSGraphicsContext.current?.saveGraphicsState()
        let glow = NSShadow(); glow.shadowColor = neon[i]; glow.shadowBlurRadius = s * 0.05; glow.set()
        neon[i].setFill(); bar.fill()
        NSGraphicsContext.current?.restoreGraphicsState()
        // Bright core
        NSColor.white.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: NSRect(x: x + bw * 0.3, y: rect.midY - h / 2 + bw * 0.3, width: bw * 0.4, height: max(0, h - bw * 0.6)), xRadius: bw * 0.2, yRadius: bw * 0.2).fill()
        x += bw + gap
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
