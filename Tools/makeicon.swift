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
    // Iridescent sheen — the project's ONE sanctioned gradient, icon only. The no-gradient rule
    // governs UI chrome (.tint(.white), no colored chrome); nothing in the app draws like this.
    // A CD without its sheen is an anonymous disc, which is why the flat version was rejected.
    //
    // Conic sweep built from wedges by hand: CGGradient does axial and radial only, so there is
    // no conic primitive to reach for. Held below full saturation so it still reads as a disc
    // rather than a pinwheel. FLAT=1 renders the ridge-less monotone disc instead.
    if ProcessInfo.processInfo.environment["FLAT"] == nil {
        let steps = 720
        for i in 0..<steps {
            let a0 = Double(i) / Double(steps) * 360, a1 = Double(i + 1) / Double(steps) * 360
            let wedge = NSBezierPath()
            wedge.move(to: c)
            // +0.5° overlap: exactly abutting wedges leave hairline seams of the layer beneath.
            wedge.appendArc(withCenter: c, radius: 360, startAngle: a0, endAngle: a1 + 0.5)
            wedge.close()
            NSColor(calibratedHue: CGFloat(i) / CGFloat(steps),
                    saturation: 0.42, brightness: 1, alpha: 1).setFill()
            wedge.fill()
        }

        // Diffraction striations over the sheen: vertical lines at three scales, so the banding
        // repeats coarse-inside-fine rather than reading as one even comb. Strongest through the
        // centre and fading toward the rim.
        NSGraphicsContext.saveGraphicsState()
        circle(360).addClip()
        for (spacing, baseAlpha) in [(96.0, 0.20), (33.0, 0.13), (11.0, 0.08)] {
            var x = -360.0
            while x <= 360 {
                let d = abs(x) / 360                     // 0 at centre, 1 at the rim
                NSColor(calibratedWhite: 1, alpha: baseAlpha * (1 - d * 0.85)).setFill()
                NSRect(x: c.x + x, y: c.y - 360, width: spacing * 0.3, height: 720).fill()
                x += spacing
            }
        }
        NSGraphicsContext.restoreGraphicsState()
    }

    // Square sticker-hole, centred on the disc's right rim. Plate-coloured, so it reads as a
    // square punched clean through the disc — app icons can't carry real alpha. The half that
    // falls beyond the rim is plate-on-plate and invisible, leaving a bite out of the edge.
    // Tuning knobs — this is a drawing, and the numbers only settle by looking at it.
    // SQ = square size. SQX = distance of its centre from the disc's centre; at 360 it straddles
    // the rim (chosen), below ~300 it sits inside the disc, and it must clear the centre hole
    // (r=150) or the two merge into a keyhole.
    let env = ProcessInfo.processInfo.environment
    let s = CGFloat(env["SQ"].flatMap(Double.init) ?? 240)
    let dx = CGFloat(env["SQX"].flatMap(Double.init) ?? 360)
    let sq = NSRect(x: c.x + dx - s / 2, y: c.y - s / 2, width: s, height: s)

    // Transparent, but outlined — the square has to read AS a square. Plate-coloured fill alone
    // is invisible against the plate, so it only ever looked like a bite out of the disc (the
    // "C"). The stroke gives it edges on both the disc and the plate, so it reads as a
    // see-through square laid over the rim.
    plate.setFill()
    sq.fill()
    ink.setStroke()
    let outline = NSBezierPath(rect: sq)
    outline.lineWidth = CGFloat(env["SQW"].flatMap(Double.init) ?? 12)
    outline.stroke()

    // Centre hole: white ring around a plate-coloured bore.
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
