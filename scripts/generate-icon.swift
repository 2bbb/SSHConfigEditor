import AppKit

let output = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSGraphicsContext.current!.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 180, yRadius: 180)
        NSColor(srgbRed: 0.12, green: 0.20, blue: 0.27, alpha: 1).setFill(); tile.fill()
        let terminal = NSBezierPath(roundedRect: NSRect(x: 228, y: 300, width: 568, height: 436), xRadius: 50, yRadius: 50)
        NSColor.white.withAlphaComponent(0.95).setStroke(); terminal.lineWidth = 30; terminal.stroke()
        let prompt = NSBezierPath()
        prompt.move(to: NSPoint(x: 320, y: 565)); prompt.line(to: NSPoint(x: 405, y: 495)); prompt.line(to: NSPoint(x: 320, y: 425))
        prompt.lineWidth = 40; prompt.lineCapStyle = .round; prompt.lineJoinStyle = .round; prompt.stroke()
        let branch = NSBezierPath()
        branch.move(to: NSPoint(x: 505, y: 560)); branch.line(to: NSPoint(x: 505, y: 430)); branch.line(to: NSPoint(x: 670, y: 430))
        branch.move(to: NSPoint(x: 505, y: 530)); branch.line(to: NSPoint(x: 670, y: 530))
        NSColor(srgbRed: 0.48, green: 0.85, blue: 0.79, alpha: 1).setStroke()
        branch.lineWidth = 26; branch.lineCapStyle = .round; branch.lineJoinStyle = .round; branch.stroke()
        NSGraphicsContext.restoreGraphicsState()
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"))
    }
}
