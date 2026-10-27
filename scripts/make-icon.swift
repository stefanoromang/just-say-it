// Just Say It – created by Stefano Roman Gunness
// MIT License · https://github.com/stefanoromang/just-say-it

import AppKit

// Renders the app icon: a waveform on a violet-to-blue rounded square.
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
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(colors: [NSColor(red: 0.49, green: 0.30, blue: 1.0, alpha: 1),
                        NSColor(red: 0.13, green: 0.55, blue: 1.0, alpha: 1)])!.draw(in: path, angle: -60)
    let bars: [CGFloat] = [0.28, 0.5, 0.78, 0.5, 0.92, 0.6, 0.36]
    let bw = rect.width * 0.075, gap = rect.width * 0.045
    let total = CGFloat(bars.count) * bw + CGFloat(bars.count - 1) * gap
    var x = rect.midX - total / 2
    NSColor.white.setFill()
    for b in bars {
        let h = rect.height * 0.62 * b
        NSBezierPath(roundedRect: NSRect(x: x, y: rect.midY - h / 2, width: bw, height: h), xRadius: bw / 2, yRadius: bw / 2).fill()
        x += bw + gap
    }
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
