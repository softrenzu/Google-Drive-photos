import AppKit
import Foundation

// Generate a simple 1024px App Store icon on macOS before XcodeGen.
// Keeps the icon source text-only for a reproducible GitHub Actions build.
let size = 1024
guard let image = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: size,
    pixelsHigh: size,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: image) else {
    fatalError("Unable to allocate icon")
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
NSGraphicsContext.current?.imageInterpolation = .high

NSColor(calibratedRed: 0.08, green: 0.25, blue: 0.43, alpha: 1.0).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: size, height: size)).fill()

// Subtle blue tile, white document and three checklist lines.
NSColor(calibratedRed: 0.13, green: 0.42, blue: 0.64, alpha: 1.0).setFill()
NSBezierPath(roundedRect: NSRect(x: 130, y: 134, width: 764, height: 764),
             xRadius: 180, yRadius: 180).fill()
NSColor.white.setFill()
NSBezierPath(roundedRect: NSRect(x: 283, y: 226, width: 458, height: 592),
             xRadius: 58, yRadius: 58).fill()

for y in [655.0, 510.0, 365.0] {
    NSColor(calibratedRed: 0.11, green: 0.54, blue: 0.69, alpha: 1.0).setFill()
    NSBezierPath(roundedRect: NSRect(x: 330, y: y, width: 70, height: 70),
                 xRadius: 16, yRadius: 16).fill()
    NSColor(calibratedWhite: 0.78, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 425, y: y + 14, width: 245, height: 25),
                 xRadius: 12, yRadius: 12).fill()
}
context.flushGraphics()
NSGraphicsContext.restoreGraphicsState()

let directory = "App/Assets.xcassets/AppIcon.appiconset"
try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
guard let data = image.representation(using: .png, properties: [:]) else {
    fatalError("PNG conversion failed")
}
try data.write(to: URL(fileURLWithPath: directory + "/AppIcon.png"), options: .atomic)
let contents = """
{
  "images": [
    {
      "filename": "AppIcon.png",
      "idiom": "universal",
      "platform": "ios",
      "size": "1024x1024"
    }
  ],
  "info": {
    "author": "xcode",
    "version": 1
  }
}
"""
try contents.write(toFile: directory + "/Contents.json", atomically: true, encoding: .utf8)
print("Generated iOS AppIcon at \(directory)")
