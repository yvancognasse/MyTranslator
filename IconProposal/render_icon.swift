import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// A proposed icon only. The application's current MyTranslator.png is untouched.
let destination = CommandLine.arguments.dropFirst().first ?? "MyTranslator-Modern.png"
let size = 1024
let colorSpace = CGColorSpaceCreateDeviceRGB()
let pixels = UnsafeMutablePointer<UInt8>.allocate(capacity: size * size * 4)
pixels.initialize(repeating: 0, count: size * size * 4)
defer { pixels.deallocate() }
guard let context = CGContext(data: pixels, width: size, height: size,
                              bitsPerComponent: 8, bytesPerRow: size * 4,
                              space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("Unable to create drawing context")
}

func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: colorSpace, components: [r / 255, g / 255, b / 255, a])!
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

// The quiet cobalt tile keeps its shape and contrast at Dock and menu sizes.
let tile = roundedRect(CGRect(x: 64, y: 64, width: 896, height: 896), radius: 210)
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -16), blur: 25, color: color(13, 31, 75, 0.24))
context.addPath(tile)
context.setFillColor(color(24, 64, 166))
context.fillPath()
context.restoreGState()

context.saveGState()
context.addPath(tile)
context.clip()
let background = CGGradient(colorsSpace: colorSpace,
                            colors: [color(23, 45, 121), color(36, 95, 218), color(65, 137, 243)] as CFArray,
                            locations: [0, 0.58, 1])!
context.drawLinearGradient(background, start: CGPoint(x: 140, y: 130), end: CGPoint(x: 900, y: 910), options: [])
context.restoreGState()

// Two exchanged text cards form a simple, language-neutral translation mark.
let rear = CGMutablePath()
rear.addRoundedRect(in: CGRect(x: 193, y: 420, width: 485, height: 326), cornerWidth: 103, cornerHeight: 103)
rear.move(to: CGPoint(x: 284, y: 453))
rear.addLine(to: CGPoint(x: 244, y: 341))
rear.addLine(to: CGPoint(x: 381, y: 425))
rear.closeSubpath()
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -15), blur: 24, color: color(7, 34, 99, 0.24))
context.addPath(rear)
context.setFillColor(color(255, 255, 255))
context.fillPath()
context.restoreGState()

// The A is a single large glyph instead of tiny multilingual lettering.
let letter = NSAttributedString(string: "A", attributes: [
    .font: NSFont.systemFont(ofSize: 214, weight: .bold),
    .foregroundColor: NSColor(calibratedRed: 35/255, green: 82/255, blue: 177/255, alpha: 1)
])
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
letter.draw(at: CGPoint(x: 291, y: 481))
NSGraphicsContext.restoreGraphicsState()

let front = CGMutablePath()
front.addRoundedRect(in: CGRect(x: 450, y: 292, width: 384, height: 302), cornerWidth: 99, cornerHeight: 99)
front.move(to: CGPoint(x: 709, y: 327))
front.addLine(to: CGPoint(x: 801, y: 222))
front.addLine(to: CGPoint(x: 793, y: 364))
front.closeSubpath()
context.saveGState()
context.setShadow(offset: CGSize(width: 0, height: -15), blur: 25, color: color(6, 35, 91, 0.25))
context.addPath(front)
context.setFillColor(color(76, 226, 204))
context.fillPath()
context.restoreGState()

// Three broad strokes read as converted text even at 32 pixels.
context.setStrokeColor(color(14, 79, 118))
context.setLineWidth(31)
context.setLineCap(.round)
for (x1, x2, y) in [(546.0, 739.0, 495.0), (546.0, 701.0, 439.0), (546.0, 660.0, 383.0)] {
    context.move(to: CGPoint(x: x1, y: y))
    context.addLine(to: CGPoint(x: x2, y: y))
    context.strokePath()
}

guard let image = context.makeImage(),
      let output = CGImageDestinationCreateWithURL(URL(fileURLWithPath: destination) as CFURL,
                                                    UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Unable to write PNG")
}
CGImageDestinationAddImage(output, image, nil)
guard CGImageDestinationFinalize(output) else { fatalError("PNG export failed") }
