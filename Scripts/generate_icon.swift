import AppKit
import ImageIO
import UniformTypeIdentifiers

// Original vector artwork shared by the app icon and transparent in-app mark.
let size = 1024

func drawArtwork() {
    NSGraphicsContext.saveGraphicsState()
    let rotation = AffineTransform(translationByX: 512, byY: 512)
    var transform = rotation
    transform.rotate(byDegrees: -12)
    transform.translate(x: -512, y: -512)
    (transform as NSAffineTransform).concat()
    let rear = NSBezierPath(roundedRect: NSRect(x: 218, y: 206, width: 546, height: 608), xRadius: 67, yRadius: 67)
    NSColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 0.45).setStroke()
    rear.lineWidth = 22
    rear.stroke()
    NSGraphicsContext.restoreGraphicsState()

    let card = NSBezierPath(roundedRect: NSRect(x: 276, y: 196, width: 522, height: 618), xRadius: 64, yRadius: 64)
    NSColor.white.setFill()
    card.fill()
    let accent = NSColor(red: 0.851, green: 0.467, blue: 0.341, alpha: 1)
    let star = NSBezierPath()
    let center = NSPoint(x: 537, y: 555)
    for index in 0..<8 {
        let angle = CGFloat(index) * .pi / 4
        let radius: CGFloat = index.isMultiple(of: 2) ? 118 : 34
        let point = NSPoint(x: center.x + sin(angle) * radius, y: center.y + cos(angle) * radius)
        if index == 0 { star.move(to: point) } else { star.line(to: point) }
    }
    star.close()
    accent.setFill()
    star.fill()
    accent.withAlphaComponent(0.18).setFill()
    NSBezierPath(roundedRect: NSRect(x: 400, y: 350, width: 274, height: 22), xRadius: 11, yRadius: 11).fill()
    NSBezierPath(roundedRect: NSRect(x: 442, y: 302, width: 190, height: 22), xRadius: 11, yRadius: 11).fill()
}

func writeIcon(to path: String, transparent: Bool) {
    let bitmapInfo = transparent ? CGImageAlphaInfo.premultipliedLast.rawValue : CGImageAlphaInfo.noneSkipLast.rawValue
    let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo)!
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    if !transparent {
        NSGradient(starting: NSColor(red: 0.977, green: 0.977, blue: 0.969, alpha: 1), ending: NSColor(red: 0.941, green: 0.937, blue: 0.925, alpha: 1))!.draw(in: NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)), angle: -55)
    }
    drawArtwork()
    let url = URL(fileURLWithPath: path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(output, context.makeImage()!, nil)
    guard CGImageDestinationFinalize(output) else { fatalError("Could not save icon") }
}

let target = CommandLine.arguments.dropFirst().first ?? "OpenAnkiIOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let markTarget = CommandLine.arguments.dropFirst(2).first ?? "OpenAnkiIOS/Assets.xcassets/AppMark.imageset/AppMark.png"
writeIcon(to: target, transparent: false)
writeIcon(to: markTarget, transparent: true)
