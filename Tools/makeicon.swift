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

/// How strongly the sheen shows at `ang`, peaking at `around` and falling to 0 by `width`.
/// Wraps across 0/360.
func sheen(_ ang: Double, around: Double, width: Double = 62) -> Double {
    var d = abs(ang - around).truncatingRemainder(dividingBy: 360)
    if d > 180 { d = 360 - d }
    let t = d / width
    return t >= 1 ? 0 : 1 - t * t
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
        // Sheen matched to reference.jpg: the disc is DARK, near-black through the top and
        // bottom, with vivid iridescence blazing through the left and right sectors. A pale
        // silver disc with pastel arcs is the opposite of how a lit CD actually photographs.
        NSGraphicsContext.saveGraphicsState()
        circle(360).addClip()

        // Flat sectors with hard separations, not a sweep. A restricted, deliberately COOL
        // palette: the full spectrum put reds and magentas directly behind the red square, which
        // is what made the red read as muddy. In reference.jpg the disc is green/yellow exactly
        // where the tape sits, so the red has something to pop against. Dark sectors interleave
        // to keep the reference's unlit bands.
        // Smooth iridescence cut by dark radial divisions — NOT equal flat sectors. Carving a
        // disc into equal coloured wedges reads as a pie chart no matter how few colours are
        // used (tried at 16 and at 8; both were beach balls). In reference.jpg the flatness comes
        // from smooth colour interrupted by dark bands.
        //
        // Hue is restricted to the cool half (green -> cyan -> violet). The full spectrum put
        // red and magenta directly behind the red square, which is what made the red read as
        // muddy; in the reference the disc is green where the tape lands.
        let divisions = [30.0, 90, 150, 210, 270, 330]
        let steps = 1440
        for i in 0..<steps {
            let ang = Double(i) / Double(steps) * 360
            var m = max(sheen(ang, around: 0, width: 78), sheen(ang, around: 180, width: 78))
            for d in divisions { m *= 1 - 0.92 * sheen(ang, around: d, width: 9) }
            let wedge = NSBezierPath()
            wedge.move(to: c)
            // +0.5° overlap: exactly abutting wedges leave hairline seams of the layer beneath.
            wedge.appendArc(withCenter: c, radius: 360,
                            startAngle: ang, endAngle: ang + 360 / Double(steps) + 0.5)
            wedge.close()
            let t = (ang / 180).truncatingRemainder(dividingBy: 1)     // two cycles
            NSColor(calibratedHue: CGFloat(0.28 + 0.45 * t),
                    saturation: CGFloat(0.75 * m),
                    brightness: CGFloat(0.18 + 0.8 * m), alpha: 1).setFill()
            wedge.fill()
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
    // Proportions measured off reference.jpg rather than guessed. There the disc is 379px across
    // and the red is 167 x 203 — i.e. 0.44 of the disc wide, 0.54 tall, and TALLER THAN WIDE,
    // not square. Its left edge starts about 0.34 of the radius out from centre.
    let env = ProcessInfo.processInfo.environment
    let height = CGFloat(env["SQH"].flatMap(Double.init) ?? 0.54) * 720
    let left = c.x + CGFloat(env["SQL"].flatMap(Double.init) ?? 0.34) * 360
    // Stretched to the icon's right edge, so it bleeds off rather than floating.
    let right = CGFloat(env["SQR"].flatMap(Double.init) ?? Double(size))
    let sq = NSRect(x: left, y: c.y - height / 2, width: right - left, height: height)

    // Solid red tape, per reference.jpg. Not plate-coloured: that would be a hole punched
    // through the disc, which is what made the icon read as a "C".
    NSColor(calibratedRed: 0.94, green: 0.14, blue: 0.11, alpha: 1).setFill()
    sq.fill()

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
