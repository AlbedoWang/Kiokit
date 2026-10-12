import AppKit
import ImageIO
import UniformTypeIdentifiers

// Vector-drawn icon; no external artwork or generation service is needed.
let size = 1024
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
NSGradient(starting: NSColor(red: 0.977, green: 0.977, blue: 0.969, alpha: 1), ending: NSColor(red: 0.941, green: 0.937, blue: 0.925, alpha: 1))!.draw(in: NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)), angle: -55)

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
NSGraphicsContext.restoreGraphicsState()

let target = CommandLine.arguments.dropFirst().first ?? "OpenAnkiIOS/Assets.xcassets/AppIcon.appiconset/AppIcon.png"
let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: target) as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(output, context.makeImage()!, nil)
guard CGImageDestinationFinalize(output) else { fatalError("Could not save icon") }
