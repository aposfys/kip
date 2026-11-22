import SwiftUI

/// kip. One parts list drives the SwiftUI drawing, the master SVGs in Design/robot
/// (`kip --svg <dir>`) and the menu-bar icon, so they cannot drift apart. Shape and colour follow
/// KIP-SPEC.md: a long, low slab with a paler back layer behind it, the face on the left half and a
/// thin antenna from the top middle. Mood shows in posture and eyes as well as colour.
/// Design space is 120×120 with y pointing down, the same as the SVGs.
enum Robot {
    /// One mood's colours (KIP-SPEC, "Mood colours").
    struct Palette: Equatable {
        var body: UInt32
        var back: UInt32
        var line: UInt32
        var ball: UInt32 = Ink.coral
    }

    enum Ink {
        static let coral: UInt32 = 0xFF7A5C   // blush and antenna ball
        static let alarm: UInt32 = 0xFF3B30   // the worried antenna ball
        static let eye: UInt32 = 0xFFFFFF
        static let paper: UInt32 = 0xFBF7EF

        static func palette(_ mood: Mood, stale: Bool = false) -> Palette {
            if stale { return Palette(body: 0xC9C2B0, back: 0xE6E1D5, line: 0x6B6555, ball: 0xD8A797) }
            switch mood {
            case .resting: return Palette(body: 0x7A7FD9, back: 0xC5C8F5, line: 0x2B2E6B)
            case .calm: return Palette(body: 0x5AB8FF, back: 0xA9DBFF, line: 0x1F5A96)
            case .happy: return Palette(body: 0xFFC83D, back: 0xFFE7A3, line: 0x6B4A00)
            case .busy: return Palette(body: 0x2BD4C5, back: 0xA6F0EA, line: 0x0D5C55)
            case .worried: return Palette(body: 0xFF8A4C, back: 0xFFC9A8, line: 0x7A2E0B, ball: alarm)
            }
        }
    }

    static let box = CGRect(x: 0, y: 0, width: 120, height: 120)
    /// The menu-bar icon's own space: a flat slab with the eyes standing above it, 18 pt tall.
    static let glyphBox = CGRect(x: 0, y: -2, width: 64, height: 42)

    struct Part {
        enum Geometry {
            case rect(CGRect, radius: CGFloat)
            case circle(CGPoint, radius: CGFloat)
            /// SVG path data, absolute M/L/H/V/C/Q/Z only (see `Robot.path`).
            case path(String)
        }

        var geometry: Geometry
        var color: UInt32
        var stroked = false
        var width: CGFloat = 2.6
        var opacity: Double = 1
        /// The pose: how far the body is lifted and bounced, applied after the shape.
        var pose: CGAffineTransform = .identity
        /// Drawn only inside this shape, in the part's own space (the hatching inside the body).
        var clip: Geometry? = nil
    }

    /// Lifts the front (left) end by `degrees`, rolling on the tail's rounded corner at `corner`.
    static func pose(lift degrees: Double, dy: CGFloat = 0, around corner: CGPoint) -> CGAffineTransform {
        CGAffineTransform(translationX: corner.x, y: corner.y + dy)
            .rotated(by: degrees * .pi / 180)
            .translatedBy(x: -corner.x, y: -corner.y)
    }

    /// kip in one mood. `phase` (seconds) animates it in the app; widgets pass nil and stay still.
    /// `glyph` builds the small menu-bar icon instead. Stale data overrides the mood's face and pose.
    static func parts(_ mood: Mood, stale: Bool = false, phase: Double? = nil, glyph: Bool = false) -> [Part] {
        glyph ? glyphParts(mood, stale: stale) : fullParts(mood, stale: stale, phase: phase)
    }

    private static func fullParts(_ mood: Mood, stale: Bool, phase: Double?) -> [Part] {
        let ink = Ink.palette(mood, stale: stale)
        let m: Mood? = stale ? nil : mood   // nil: stale, still and plain
        func wave(_ period: Double, _ offset: Double = 0) -> Double {
            guard let phase, m != nil else { return 0 }
            return sin((phase / period + offset) * 2 * .pi)
        }

        // Body: squashed flat when resting (and breathing), otherwise the 2.6 : 1 slab on the ground at y 97.
        var b = m == .resting ? CGRect(x: 6, y: 69, width: 98, height: 28) : CGRect(x: 10, y: 61, width: 90, height: 36)
        if m == .resting { let breath = 1.2 * wave(4.5); b.origin.y -= breath; b.size.height += breath }
        let r = b.height * 0.47
        var lift = 0.0
        if m == .busy { lift = 14 }
        if m == .worried { lift = 28 + 1.2 * wave(0.21) }
        let bounce: CGFloat = m == .happy ? -3 * max(0, wave(1.1)) : 0
        let pose = Robot.pose(lift: lift, dy: bounce, around: CGPoint(x: b.maxX - r, y: b.maxY - r))

        var out: [Part] = [Part(geometry: .path("M16 99.5 C40 98.6 76 100.2 104 99.2"), color: ink.line, stroked: true,
                                width: 1.4, opacity: 0.2)]   // pencil ground line
        func add(_ g: Part.Geometry, _ c: UInt32, stroked: Bool = false, width: CGFloat = 2.6, opacity: Double = 1,
                 clip: Part.Geometry? = nil) {
            out.append(Part(geometry: g, color: c, stroked: stroked, width: width, opacity: opacity, pose: pose, clip: clip))
        }
        /// A pencil line: the main stroke plus a faint second pass just off it.
        func pencil(_ g: Part.Geometry, _ c: UInt32, width: CGFloat = 2.6) {
            add(g, c, stroked: true, width: width, opacity: 0.92)
            out.append(Part(geometry: g, color: c, stroked: true, width: width * 0.4, opacity: 0.35,
                            pose: CGAffineTransform(translationX: 0.8, y: -0.6).concatenating(pose)))
        }

        // Back layer one tone paler, offset behind and to the right; then the hatched front.
        let back = b.offsetBy(dx: 6, dy: -4)
        add(.rect(back, radius: r), ink.back)
        pencil(.rect(back, radius: r), ink.line, width: 1.8)
        add(.rect(b, radius: r), ink.body, opacity: 0.94)
        add(.path(hatch(b)), ink.line, stroked: true, width: 1, opacity: 0.13, clip: .rect(b, radius: r))
        pencil(.rect(b, radius: r), ink.line)

        // Antenna from the top middle: curved and leaning right, straight up when happy.
        let top = CGPoint(x: b.midX, y: b.minY)
        let straight = m == .happy
        let tip = straight ? CGPoint(x: top.x, y: top.y - 21) : CGPoint(x: top.x + 7, y: top.y - 19)
        let ball = straight ? CGPoint(x: tip.x, y: tip.y - 4.5) : CGPoint(x: tip.x + 1.6, y: tip.y - 3.6)
        add(.path(straight ? "M\(n(top.x)) \(n(top.y)) L\(n(tip.x)) \(n(tip.y))"
                  : "M\(n(top.x)) \(n(top.y)) C\(n(top.x - 1)) \(n(top.y - 8)) \(n(top.x + 1)) \(n(top.y - 15)) \(n(tip.x)) \(n(tip.y))"),
            ink.line, stroked: true, width: 2.2)
        if m == .busy {
            add(.circle(ball, radius: 9.5 + 1.2 * wave(1.2)), ink.ball, opacity: 0.3 + 0.12 * wave(1.2))
        }
        add(.circle(ball, radius: 5), ink.ball, opacity: m == .resting ? 0.6 : 1)
        pencil(.circle(ball, radius: 5), ink.line, width: 1.4)

        // Face on the left half: eyes, blush under them, mouth between.
        let ey = b.minY + b.height * 0.42
        let eyes = [b.minX + b.width * 0.22, b.minX + b.width * 0.38]
        let mx = (eyes[0] + eyes[1]) / 2, my = ey + (m == .resting ? 8.5 : 13)
        if m != nil {
            for (x, dx) in zip(eyes, [-7.0, 7.0]) {
                add(.circle(CGPoint(x: x + dx, y: ey + 10), radius: 3.6), Ink.coral, opacity: 0.75)
            }
        }
        let blink = m == .calm && (phase.map { $0.truncatingRemainder(dividingBy: 4.3) < 0.15 } ?? false)
        func pill(_ x: CGFloat) -> CGRect { CGRect(x: x - 5, y: ey - 9, width: 10, height: 18) }
        func line(_ d: String, width: CGFloat = 2.6) { add(.path(d), ink.line, stroked: true, width: width) }

        switch m {
        case nil:   // stale: dot eyes, flat mouth
            for x in eyes { add(.circle(CGPoint(x: x, y: ey), radius: 2.8), ink.line) }
            line("M\(n(mx - 4)) \(n(my)) L\(n(mx + 4)) \(n(my))")
        case .resting:   // closed eyes, little "o"
            for x in eyes { line("M\(n(x - 5)) \(n(ey)) Q\(n(x)) \(n(ey + 4.5)) \(n(x + 5)) \(n(ey))") }
            add(.circle(CGPoint(x: mx, y: my), radius: 2.1), ink.line, stroked: true, width: 2)
        case .calm, .busy:   // pill eyes; busy's pupils are spinning loading rings
            for x in eyes {
                if blink { line("M\(n(x - 5)) \(n(ey)) Q\(n(x)) \(n(ey + 2.5)) \(n(x + 5)) \(n(ey))"); continue }
                add(.rect(pill(x), radius: 5), Ink.eye)
                pencil(.rect(pill(x), radius: 5), ink.line, width: 2.2)
                if m == .busy {
                    line(arc(CGPoint(x: x, y: ey), 3, from: -90 + (phase ?? 0) * 300, sweep: 270), width: 1.9)
                } else {
                    add(.rect(CGRect(x: x - 2, y: ey - 4.5, width: 4, height: 9), radius: 2), ink.line)
                }
            }
            line(m == .busy ? "M\(n(mx - 3.5)) \(n(my)) Q\(n(mx)) \(n(my + 1.5)) \(n(mx + 3.5)) \(n(my))"
                            : "M\(n(mx - 4)) \(n(my - 1)) Q\(n(mx)) \(n(my + 3)) \(n(mx + 4)) \(n(my - 1))")
        case .happy:   // smiling eyes, open grin
            for x in eyes { line("M\(n(x - 5)) \(n(ey + 3)) Q\(n(x)) \(n(ey - 7)) \(n(x + 5)) \(n(ey + 3))", width: 3) }
            add(.path("M\(n(mx - 5.5)) \(n(my - 2)) L\(n(mx + 5.5)) \(n(my - 2)) C\(n(mx + 5.5)) \(n(my + 3)) \(n(mx + 3)) \(n(my + 5)) \(n(mx)) \(n(my + 5)) C\(n(mx - 3)) \(n(my + 5)) \(n(mx - 5.5)) \(n(my + 3)) \(n(mx - 5.5)) \(n(my - 2)) Z"),
                ink.line)
        case .worried:   // X eyes, wobbly mouth
            for x in eyes {
                line("M\(n(x - 4)) \(n(ey - 4.5)) L\(n(x + 4)) \(n(ey + 4.5)) M\(n(x + 4)) \(n(ey - 4.5)) L\(n(x - 4)) \(n(ey + 4.5))", width: 3)
            }
            line("M\(n(mx - 6)) \(n(my)) Q\(n(mx - 3)) \(n(my - 3)) \(n(mx)) \(n(my)) Q\(n(mx + 3)) \(n(my + 3)) \(n(mx + 6)) \(n(my))")
        }

        // Effects around kip. They stay upright and follow the posed antenna ball.
        let bp = ball.applying(pose)
        switch m {
        case .resting:
            for (i, (d, o)) in [("M84 50 L92 50 L84 58 L92 58", 0.8), ("M97 36 L103 36 L97 42 L103 42", 0.6)].enumerated() {
                out.append(Part(geometry: .path(d), color: ink.line, stroked: true, width: 2.2,
                                opacity: o * (0.85 + 0.15 * wave(4.5, Double(i) * 0.3))))
            }
        case .happy:
            for (i, (c, s, color)) in [(CGPoint(x: bp.x + 17, y: bp.y + 4), 5.5, Ink.coral),
                                       (CGPoint(x: bp.x - 16, y: bp.y + 9), 4.0, ink.line),
                                       (CGPoint(x: bp.x + 27, y: bp.y + 19), 3.2, ink.line)].enumerated() {
                out.append(Part(geometry: .path(sparkle(c, s * (1 + 0.25 * wave(1.4, Double(i) * 0.3)))),
                                color: color, opacity: 0.85))
            }
        case .worried:
            for (i, deg) in [-150.0, -95, -40].enumerated() {
                let a = deg * .pi / 180, u = CGPoint(x: cos(a), y: sin(a))
                out.append(Part(geometry: .path("M\(n(bp.x + 9 * u.x)) \(n(bp.y + 9 * u.y)) L\(n(bp.x + 15 * u.x)) \(n(bp.y + 15 * u.y))"),
                                color: Ink.alarm, stroked: true, width: 2.4, opacity: 0.7 + 0.3 * wave(0.3, Double(i) * 0.37)))
            }
        default:
            break
        }
        return out
    }

    /// The menu-bar icon: a flat slab, eyes standing above it, antenna to the right. Bold lines, no
    /// hatching, so it stays crisp at 18 pt. It lies flat until something needs you, then it lifts
    /// and its ball glows.
    private static func glyphParts(_ mood: Mood, stale: Bool) -> [Part] {
        let ink = Ink.palette(mood, stale: stale)
        let m: Mood? = stale ? nil : mood
        let slab = CGRect(x: 3, y: 22, width: 54, height: 16), r: CGFloat = 8
        let lift = m == .worried ? 13.0 : m == .busy ? 7 : 0
        let pose = Robot.pose(lift: lift, around: CGPoint(x: slab.maxX - r, y: slab.maxY - r))
        var out: [Part] = []
        func add(_ g: Part.Geometry, _ c: UInt32, stroked: Bool = false, width: CGFloat = 2.6, opacity: Double = 1) {
            out.append(Part(geometry: g, color: c, stroked: stroked, width: width, opacity: opacity, pose: pose))
        }

        let straight = m == .happy
        let ball = straight ? CGPoint(x: 42, y: 5.5) : CGPoint(x: 48.5, y: 7.5)
        add(.rect(slab, radius: r), ink.body)
        add(.rect(slab, radius: r), ink.line, stroked: true)
        add(.path(straight ? "M42 22 L42 10" : "M42 22 L47 11.5"), ink.line, stroked: true, width: 2.4)
        if m == .busy || m == .worried { add(.circle(ball, radius: 7.5), ink.ball, opacity: 0.35) }
        add(.circle(ball, radius: 4.2), ink.ball)
        add(.circle(ball, radius: 4.2), ink.line, stroked: true, width: 1.6)
        for x: CGFloat in [17, 29] {
            if m == .resting {   // closed eyes lie on the slab, so resting reads by shape too
                add(.path("M\(n(x - 4.5)) 27.5 Q\(n(x)) 32 \(n(x + 4.5)) 27.5"), ink.line, stroked: true, width: 2.4)
            } else {
                let eye = CGRect(x: x - 4.5, y: 12, width: 9, height: 18)
                add(.rect(eye, radius: 4.5), Ink.eye)
                add(.rect(eye, radius: 4.5), ink.line, stroked: true, width: 2.4)
                add(.rect(CGRect(x: x - 1.6, y: 16.5, width: 3.2, height: 9), radius: 1.6), ink.line)
            }
        }
        return out
    }

    // MARK: Path helpers

    /// Diagonal pencil hatching across a rect; parts clip it to the body.
    static func hatch(_ r: CGRect, gap: CGFloat = 4) -> String {
        var d = ""
        var x = r.minX - r.height
        while x < r.maxX {
            d += "M\(n(x)) \(n(r.maxY)) L\(n(x + r.height)) \(n(r.minY)) "
            x += gap
        }
        return d
    }

    /// A circular arc as cubic curves, since the path parser has no A command. Angles in degrees,
    /// clockwise on screen from 3 o'clock.
    static func arc(_ c: CGPoint, _ r: CGFloat, from start: Double, sweep: Double) -> String {
        let steps = max(1, Int((abs(sweep) / 90).rounded(.up)))
        let da = sweep / Double(steps) * .pi / 180
        let k = 4 / 3 * tan(da / 4)
        var a = start * .pi / 180
        var d = "M\(n(c.x + r * cos(a))) \(n(c.y + r * sin(a)))"
        for _ in 0..<steps {
            let e = a + da
            d += " C\(n(c.x + r * (cos(a) - k * sin(a)))) \(n(c.y + r * (sin(a) + k * cos(a))))"
                + " \(n(c.x + r * (cos(e) + k * sin(e)))) \(n(c.y + r * (sin(e) - k * cos(e))))"
                + " \(n(c.x + r * cos(e))) \(n(c.y + r * sin(e)))"
            a = e
        }
        return d
    }

    /// A four-point sparkle of radius `r`.
    static func sparkle(_ c: CGPoint, _ r: CGFloat) -> String {
        let s = r * 0.28
        return "M\(n(c.x)) \(n(c.y - r)) Q\(n(c.x + s)) \(n(c.y - s)) \(n(c.x + r)) \(n(c.y))"
            + " Q\(n(c.x + s)) \(n(c.y + s)) \(n(c.x)) \(n(c.y + r)) Q\(n(c.x - s)) \(n(c.y + s)) \(n(c.x - r)) \(n(c.y))"
            + " Q\(n(c.x - s)) \(n(c.y - s)) \(n(c.x)) \(n(c.y - r)) Z"
    }

    // MARK: Drawing

    /// shortcut: parses only the absolute M/L/H/V/C/Q/Z commands used above, with space-separated
    /// numbers. Extend it before drawing arcs or relative paths.
    static func path(_ d: String) -> Path {
        var tokens: [String] = []
        for word in d.split(whereSeparator: { $0 == " " || $0 == "," || $0 == "\n" }) {
            var rest = Substring(word)
            if let c = rest.first, c.isLetter { tokens.append(String(c)); rest = rest.dropFirst() }
            if !rest.isEmpty { tokens.append(String(rest)) }
        }
        var p = Path()
        var i = 0
        var cmd = "M"
        var cur = CGPoint.zero
        func num() -> CGFloat {
            defer { i += 1 }
            return i < tokens.count ? CGFloat(Double(tokens[i]) ?? 0) : 0
        }
        func point() -> CGPoint { let x = num(); return CGPoint(x: x, y: num()) }
        while i < tokens.count {
            if let c = tokens[i].first, c.isLetter {
                cmd = tokens[i]
                i += 1
                if cmd == "Z" { p.closeSubpath(); continue }
            }
            switch cmd {
            case "M": cur = point(); p.move(to: cur); cmd = "L"
            case "L": cur = point(); p.addLine(to: cur)
            case "H": cur.x = num(); p.addLine(to: cur)
            case "V": cur.y = num(); p.addLine(to: cur)
            case "C": let c1 = point(), c2 = point(); cur = point(); p.addCurve(to: cur, control1: c1, control2: c2)
            case "Q": let c = point(); cur = point(); p.addQuadCurve(to: cur, control: c)
            default: i += 1
            }
        }
        return p
    }

    static func shape(_ g: Part.Geometry) -> Path {
        switch g {
        case let .rect(r, radius): Path(roundedRect: r, cornerRadius: radius, style: .circular)
        case let .circle(c, r): Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        case let .path(d): path(d)
        }
    }

    /// The part's outline in design space: strokes turned into fills, clipped, then posed.
    static func outline(_ part: Part) -> Path {
        var p = shape(part.geometry)
        if part.stroked { p = p.strokedPath(StrokeStyle(lineWidth: part.width, lineCap: .round, lineJoin: .round)) }
        if let clip = part.clip { p = p.intersection(shape(clip)) }
        return part.pose.isIdentity ? p : p.applying(part.pose)
    }

    // MARK: SVG

    static func svg(_ mood: Mood, stale: Bool = false, glyph: Bool = false) -> String {
        let parts = parts(mood, stale: stale, glyph: glyph)
        let b = glyph ? glyphBox : box
        let ink = Ink.palette(mood, stale: stale)
        let name = (glyph ? "menu-bar icon, " : "") + (stale ? "stale data" : mood.rawValue)
        let size = glyph ? "width=\"\(n(18 * b.width / b.height))\" height=\"18\"" : "width=\"120\" height=\"120\""
        let note = "Colours: body \(hex(ink.body)), back \(hex(ink.back)), lines \(hex(ink.line)), ball \(hex(ink.ball)), "
            + "blush \(hex(Ink.coral)), eyes #FFFFFF."
            + (glyph ? " Menu-bar size: bold lines, no hatching or wobble." : " The pencil filter wobbles each line by at most 1.2.")
        var out = """
        <svg xmlns="http://www.w3.org/2000/svg" \(size) viewBox="\(n(b.minX)) \(n(b.minY)) \(n(b.width)) \(n(b.height))" fill="none">
        <title>kip, \(name)</title>
        <!-- Generated from Shared/Robot.swift by `kip --svg <dir>`. Edit the Swift, not this file.
             \(note) -->

        """
        var defs = glyph ? "" : """
            <filter id="pencil" x="-5%" y="-5%" width="110%" height="110%">
            <feTurbulence type="fractalNoise" baseFrequency="0.9" numOctaves="2" seed="7" result="grain"/>
            <feDisplacementMap in="SourceGraphic" in2="grain" scale="1.2" xChannelSelector="R" yChannelSelector="G"/>
            </filter>

            """
        var drawn = ""
        for (i, p) in parts.enumerated() {
            if let clip = p.clip {
                defs += "<clipPath id=\"clip\(i)\">\(element(Part(geometry: clip, color: 0)).dropLast())</clipPath>\n"
                drawn += element(p, clip: "clip\(i)")
            } else {
                drawn += element(p)
            }
        }
        if !defs.isEmpty { out += "<defs>\n\(defs)</defs>\n" }
        out += glyph ? drawn : "<g filter=\"url(#pencil)\">\n\(drawn)</g>\n"
        return out + "</svg>\n"
    }

    private static func element(_ p: Part, clip: String? = nil) -> String {
        let paint = p.stroked
            ? "stroke=\"\(hex(p.color))\" stroke-width=\"\(n(p.width))\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
            : "fill=\"\(hex(p.color))\""
        var extra = p.opacity < 1 ? " opacity=\"\(n(p.opacity))\"" : ""
        if !p.pose.isIdentity {
            let t = p.pose
            extra += " transform=\"matrix(\([t.a, t.b, t.c, t.d, t.tx, t.ty].map { n($0) }.joined(separator: " ")))\""
        }
        if let clip { extra += " clip-path=\"url(#\(clip))\"" }
        switch p.geometry {
        case let .rect(r, radius):
            return "<rect x=\"\(n(r.minX))\" y=\"\(n(r.minY))\" width=\"\(n(r.width))\" height=\"\(n(r.height))\" rx=\"\(n(radius))\" \(paint)\(extra)/>\n"
        case let .circle(c, r):
            return "<circle cx=\"\(n(c.x))\" cy=\"\(n(c.y))\" r=\"\(n(r))\" \(paint)\(extra)/>\n"
        case let .path(d):
            return "<path d=\"\(d.trimmingCharacters(in: .whitespaces))\" \(paint)\(extra)/>\n"
        }
    }

    private static func hex(_ c: UInt32) -> String { String(format: "#%06X", c) }

    static func n(_ v: some BinaryFloatingPoint) -> String {
        let s = String(format: "%.2f", Double(v))
        let t = s.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        return t == "-0" ? "0" : t
    }
}

/// Whether kip animates (the app) or stays still (widgets, snapshots).
extension EnvironmentValues {
    @Entry var robotAnimates = false
}

/// kip in full colour pencil. Still unless `robotAnimates` is set and Reduce Motion is off.
struct RobotView: View {
    var mood: Mood
    var stale = false
    var label: String? = nil
    @Environment(\.robotAnimates) private var animates
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if animates && !reduceMotion {
                TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                    RobotParts(parts: Robot.parts(mood, stale: stale, phase: context.date.timeIntervalSinceReferenceDate),
                               box: Robot.box)
                }
            } else {
                RobotParts(parts: Robot.parts(mood, stale: stale), box: Robot.box)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(label ?? "kip, \(stale ? "stale" : mood.label)")
    }
}

/// The colour menu-bar icon. Size it 18 pt tall.
struct RobotGlyph: View {
    var mood: Mood
    var stale = false

    var body: some View {
        RobotParts(parts: Robot.parts(mood, stale: stale, glyph: true), box: Robot.glyphBox)
            .aspectRatio(Robot.glyphBox.width / Robot.glyphBox.height, contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel("kip, \(stale ? "stale" : mood.label)")
    }
}

struct RobotParts: View {
    var parts: [Robot.Part]
    var box: CGRect

    var body: some View {
        ZStack {
            ForEach(parts.indices, id: \.self) { i in
                let part = parts[i]
                RobotPartShape(outline: Robot.outline(part), box: box)
                    .fill(Color(hex: part.color))
                    .opacity(part.opacity)
            }
        }
    }
}

/// Fits a design-space outline into the view, centred.
struct RobotPartShape: Shape {
    var outline: Path
    var box: CGRect

    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / box.width, rect.height / box.height)
        return outline.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s,
                                                  tx: rect.midX - box.midX * s, ty: rect.midY - box.midY * s))
    }
}
