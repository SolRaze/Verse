// Regenerates the app icon. Not part of any target — run it by hand:
//
//   swiftc Tools/makeicon.swift -o /tmp/makeicon && /tmp/makeicon vinyl \
//     Assets/Assets.xcassets/AppIcon.appiconset/icon1024.png
//
// Monotone by rule: no gradients anywhere in this project, which is also why the CD style is
// unused — a CD without its iridescent sheen is just a disc.
import AppKit

_ = NSApplication.shared          // AppKit needs an app instance before NSImage/drawing works

let style = CommandLine.arguments[1]        // "vinyl" | "cd"
let path = CommandLine.arguments[2]
let size = 1024.0

// Explicit opaque bitmap: lockFocus() honours the Retina backing scale (silently yielding 2048
// with alpha) and traps with no window context. 3 samples at 32bpp maps to alphaNoneSkipLast —
// CoreGraphics can't back a 24bpp context, and this still encodes PNG with no alpha.
guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32) else { fatalError("no bitmap") }
rep.size = NSSize(width: size, height: size)

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

let plate = NSColor(calibratedWhite: 0.11, alpha: 1)
let ink = NSColor.white
let c = NSPoint(x: size / 2, y: size / 2)

func circle(_ r: CGFloat) -> NSBezierPath {
    NSBezierPath(ovalIn: NSRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
}

plate.setFill()
NSRect(x: 0, y: 0, width: size, height: size).fill()
ink.setFill()
circle(360).fill()

if style == "vinyl" {
    // Grooves: plate-coloured rings cut into the disc. Bold and widely spaced on purpose —
    // finer than this mushes into grey at 60pt on the home screen.
    var r: CGFloat = 170
    while r <= 330 {
        let g = circle(r)
        g.lineWidth = 7
        NSColor(calibratedWhite: 0.11, alpha: 0.6).setStroke()
        g.stroke()
        r += 40
    }
    plate.setFill()
    circle(112).fill()      // centre label
    ink.setFill()
    circle(16).fill()       // spindle hole
} else {
    for r in [300.0, 288.0] {
        let g = circle(r)
        g.lineWidth = 3
        NSColor(calibratedWhite: 0.11, alpha: 0.45).setStroke()
        g.stroke()
    }
    plate.setFill()
    circle(150).fill()
    ink.setFill()
    circle(118).fill()
    plate.setFill()
    circle(86).fill()
}

NSGraphicsContext.restoreGraphicsState()

guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("encode failed") }
try png.write(to: URL(fileURLWithPath: path))
print("wrote \(path)")
