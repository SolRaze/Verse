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

        let steps = 1440
        for i in 0..<steps {
            let ang = Double(i) / Double(steps) * 360
            // Two lobes, left and right; dark bands survive at top and bottom.
            let m = max(sheen(ang, around: 0, width: 78), sheen(ang, around: 180, width: 78))
            let wedge = NSBezierPath()
            wedge.move(to: c)
            // +0.5° overlap: exactly abutting wedges leave hairline seams of the layer beneath.
            wedge.appendArc(withCenter: c, radius: 360,
                            startAngle: ang, endAngle: ang + 360 / Double(steps) + 0.5)
            wedge.close()
            // Hue runs two full cycles around the disc, so each lit sector carries a whole
            // spectrum rather than one flat tint.
            NSColor(calibratedHue: CGFloat((ang / 180).truncatingRemainder(dividingBy: 1)),
                    saturation: CGFloat(0.9 * m),
                    brightness: CGFloat(0.16 + 0.84 * m), alpha: 1).setFill()
            wedge.fill()
        }

        // Radial streaks out from the spindle, only where the light is.
        // Kept soft: in the reference the colour does the work and the streaking is barely
        // there. Whiter or wider than this and it reads as a pinwheel again.
        let spokes = Int(ProcessInfo.processInfo.environment["SPOKES"].flatMap(Int.init) ?? 44)
        for k in 0..<spokes {
            let ang = Double(k) / Double(spokes) * 360
            let m = max(sheen(ang, around: 0, width: 78), sheen(ang, around: 180, width: 78))
            guard m > 0.08 else { continue }
            let r = ang * .pi / 180
            let streak = NSBezierPath()
            streak.move(to: NSPoint(x: c.x + cos(r) * 150, y: c.y + sin(r) * 150))
            streak.line(to: NSPoint(x: c.x + cos(r) * 360, y: c.y + sin(r) * 360))
            streak.lineWidth = 4
            NSColor(calibratedWhite: 1, alpha: CGFloat(m) * 0.18).setStroke()
            streak.stroke()
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
    let s = CGFloat(env["SQ"].flatMap(Double.init) ?? 300)
    // 310, not 360: centred exactly on the rim, a square this size runs off the icon's edge.
    let dx = CGFloat(env["SQX"].flatMap(Double.init) ?? 310)
    let sq = NSRect(x: c.x + dx - s / 2, y: c.y - s / 2, width: s, height: s)

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
