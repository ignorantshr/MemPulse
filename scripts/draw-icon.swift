import AppKit

// Vector geometry rendered at every macOS icon size, with transparent margins.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let assets = root.appendingPathComponent("Assets")
let iconset = assets.appendingPathComponent("MemPulse.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
            green: CGFloat((hex >> 8) & 255) / 255,
            blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

func roundRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

func glow(_ hex: UInt32, _ blur: CGFloat, _ draw: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(hex, 0.9)
    shadow.shadowBlurRadius = blur
    shadow.shadowOffset = .zero
    shadow.set()
    draw()
    NSGraphicsContext.restoreGraphicsState()
}

func render(size: Int, to url: URL) throws {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()

    // Dark violet tile with a soft drop shadow.
    let tile = roundRect(64, 64, 896, 896, 202)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 22 * scale
    shadow.shadowOffset = NSSize(width: 0, height: -12 * scale)
    shadow.set()
    color(0x0A0818).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [color(0x2A1650), color(0x080A1C)])!.draw(in: tile, angle: -70)

    // Faint scanline grid, skipped at tiny sizes where it turns to noise.
    if size >= 128 {
        NSGraphicsContext.saveGraphicsState()
        tile.addClip()
        color(0x22E4FF, 0.07).setStroke()
        for step in stride(from: CGFloat(128), through: 896, by: 64) {
            let h = NSBezierPath(); h.move(to: NSPoint(x: 64, y: step)); h.line(to: NSPoint(x: 960, y: step))
            let v = NSBezierPath(); v.move(to: NSPoint(x: step, y: 64)); v.line(to: NSPoint(x: step, y: 960))
            h.lineWidth = 2; v.lineWidth = 2; h.stroke(); v.stroke()
        }
        NSGraphicsContext.restoreGraphicsState()
    }
    color(0xFFFFFF, 0.12).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    // Chip pins.
    for index in 0..<4 {
        let offset = CGFloat(index) * 110 + 327
        color(0x6B7BFF, 0.75).setFill()
        roundRect(offset, 222, 40, 90, 16).fill()
        roundRect(offset, 712, 40, 90, 16).fill()
        roundRect(222, offset, 90, 40, 16).fill()
        roundRect(712, offset, 90, 40, 16).fill()
    }

    // Neon chip frame: cyan to magenta ring around a dark core.
    let chip = roundRect(282, 282, 460, 460, 96)
    glow(0x7A5CFF, 40 * scale) { color(0x7A5CFF).setFill(); chip.fill() }
    NSGradient(colors: [color(0x22E4FF), color(0x7A5CFF), color(0xFF3FD0)])!.draw(in: chip, angle: -45)
    let core = roundRect(310, 310, 404, 404, 72)
    NSGradient(colors: [color(0x14112E), color(0x090B1E)])!.draw(in: core, angle: -90)

    // Heartbeat line crossing the chip.
    let pulse = NSBezierPath()
    let points: [(CGFloat, CGFloat)] = [
        (150, 512), (352, 512), (384, 556), (416, 512), (458, 512),
        (494, 392), (548, 772), (604, 286), (642, 548), (672, 512), (874, 512)
    ]
    pulse.move(to: NSPoint(x: points[0].0, y: points[0].1))
    for p in points.dropFirst() { pulse.line(to: NSPoint(x: p.0, y: p.1)) }
    pulse.lineJoinStyle = .round
    pulse.lineCapStyle = .round
    pulse.lineWidth = 36
    glow(0x22E4FF, 46 * scale) { color(0x22E4FF).setStroke(); pulse.stroke() }
    glow(0x22E4FF, 18 * scale) { color(0x5CF2FF).setStroke(); pulse.stroke() }
    pulse.lineWidth = 14
    color(0xEFFFFF).setStroke()
    pulse.stroke()

    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: url)
}

for base in [16, 32, 128, 256, 512] {
    try render(size: base, to: iconset.appendingPathComponent("icon_\(base)x\(base).png"))
    try render(size: base * 2, to: iconset.appendingPathComponent("icon_\(base)x\(base)@2x.png"))
}
try render(size: 1024, to: assets.appendingPathComponent("MemPulse.png"))
try render(size: 256, to: assets.appendingPathComponent("MemPulse-preview.png"))
print("Rendered Assets/MemPulse.png and Assets/MemPulse.iconset")
