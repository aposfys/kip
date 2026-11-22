import SwiftUI

/// Docket the robot. One parts list drives the SwiftUI drawing, the master SVGs in
/// Design/robot (`Docket --svg <dir>`) and the menu-bar glyph, so they cannot drift apart.
/// Design space is 120×120 with y pointing down, the same as the SVGs.
enum Robot {
    /// Palette hex values, also written into every exported SVG.
    enum Ink {
        static let blue: UInt32 = 0x008BE5      // front body, motion ticks, Zzz
        static let navy: UInt32 = 0x004D80      // back body, antenna
        static let coral: UInt32 = 0xFD5C3F     // antenna ball, blush, sparks
        static let face: UInt32 = 0x002E4D      // eyes and mouth: 3.9:1 on the blue body
        static let white: UInt32 = 0xFFFFFF     // eye highlights
        static let blueSleepy: UInt32 = 0x0072BD
        static let navySleepy: UInt32 = 0x003D66
        static let black: UInt32 = 0x000000     // menu-bar template

        /// Stale data: the same robot in cool greys, so the mood still reads by shape.
        static func stale(_ c: UInt32) -> UInt32 {
            switch c {
            case blue, blueSleepy: 0x8E99A3
            case navy, navySleepy: 0x5E6A75
            case coral: 0xA9B2BA
            case face: 0x2F3A44
            default: c
            }
        }
    }

    static let stroke: CGFloat = 4.5
    static let box = CGRect(x: 0, y: 0, width: 120, height: 120)
    /// The menu-bar glyph crops the tail and effects away: body, antenna and face only.
    static let glyphBox = CGRect(x: 20, y: 6, width: 80, height: 100)
    static let pivot = CGPoint(x: 58, y: 76)

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
        var width: CGFloat = Robot.stroke
        var opacity: Double = 1
        /// Degrees around `Robot.pivot` (the worried lean).
        var tilt: Double = 0
        /// Menu-bar glyph only: cut out of the shapes below instead of drawn.
        var knockout = false
    }

    /// The robot for one mood. `phase` (seconds) animates the antenna and sparks in the app;
    /// widgets pass nil and stay still. `glyph` builds the one-colour menu-bar version.
    static func parts(_ mood: Mood, stale: Bool = false, phase: Double? = nil, glyph: Bool = false) -> [Part] {
        let sleepy = mood == .sleepy
        let lean: Double = mood == .worried ? -5 : 0
        let w = glyph ? 7 : stroke
        func wave(_ period: Double, _ offset: Double = 0) -> Double {
            guard let phase else { return 0 }
            return sin((phase / period + offset) * 2 * .pi)
        }

        var body: [Part] = []
        func add(_ g: Part.Geometry, _ c: UInt32, stroked: Bool = false, opacity: Double = 1, face: Bool = false) {
            body.append(Part(geometry: g, color: c, stroked: stroked, width: w, opacity: opacity, tilt: lean, knockout: glyph && face))
        }

        // Cable tail, then the two-tone body: navy back layer offset behind the blue front.
        if !glyph {
            add(.path("M22 90 C12 95 4 89 6 80 C8 72 19 71 20 78 C21 86 9 88 6 79 C3.5 71 7 61 13 55"), Ink.blue, stroked: true)
        }
        add(.rect(CGRect(x: 31, y: 49, width: 64, height: 56), radius: 20), sleepy ? Ink.navySleepy : Ink.navy,
            opacity: glyph ? 0.5 : 1)
        add(.rect(CGRect(x: 22, y: 46, width: 64, height: 56), radius: 20), sleepy ? Ink.blueSleepy : Ink.blue)

        // Antenna and ball. Busy adds a glowing halo ring; sleepy dims the ball.
        add(.path("M54 46 C50 37 52 28 57 23"), Ink.navy, stroked: true)
        if mood == .busy && !glyph {
            add(.circle(CGPoint(x: 58, y: 18), radius: 12.5 + 0.8 * wave(1.6)), Ink.coral, stroked: true,
                opacity: 0.35 + 0.15 * wave(1.6))
        }
        let pulse = mood == .sleepy ? 0 : 0.6 * wave(mood == .busy ? 1.6 : 2.4)
        add(.circle(CGPoint(x: 58, y: 18), radius: 7.5 + pulse), Ink.coral,
            opacity: sleepy ? 0.5 + 0.1 * wave(4) : 1)

        // Blush, everywhere except worried.
        if mood != .worried && !glyph {
            for x in [31.0, 77] { add(.circle(CGPoint(x: x, y: 82), radius: 4), Ink.coral, opacity: 0.85) }
        }

        // Face: eyes ~18% of the body width, one stroke weight.
        let eyes: [CGFloat] = [42, 66]
        switch mood {
        case .happy:
            for x in eyes {
                add(.circle(CGPoint(x: x, y: 70), radius: 6), Ink.face, face: true)
                if !glyph { add(.circle(CGPoint(x: x + 2, y: 68), radius: 2), Ink.white) }
            }
            add(.path("M47 82 Q54 91 61 82"), Ink.face, stroked: true, face: true)
        case .busy:
            for x in eyes {
                add(.path("M\(x - 6) 70 L\(x + 6) 70 C\(x + 6) 73.3 \(x + 3.3) 76 \(x) 76 C\(x - 3.3) 76 \(x - 6) 73.3 \(x - 6) 70 Z"),
                    Ink.face, face: true)
            }
            add(.path("M48.5 81 L59.5 81 C59.5 85 57.5 88 54 88 C50.5 88 48.5 85 48.5 81 Z"), Ink.face, face: true)
        case .worried:
            for x in eyes {
                add(.path("M\(x - 5) 65 L\(x + 5) 75 M\(x + 5) 65 L\(x - 5) 75"), Ink.face, stroked: true, face: true)
            }
            add(.path("M44 84 Q49 79 54 84 Q59 89 64 84"), Ink.face, stroked: true, face: true)
        case .sleepy:
            for x in eyes {
                add(.path("M\(x - 6) 70 Q\(x) 76 \(x + 6) 70"), Ink.face, stroked: true, face: true)
            }
            add(.circle(CGPoint(x: 54, y: 85), radius: 4), Ink.face, stroked: true, face: true)
        }

        // Effects beside the body. They do not lean with it.
        var effects: [Part] = []
        if !glyph {
            switch mood {
            case .busy:
                for (i, d) in ["M100 64 L112 64", "M103 76 L112 76"].enumerated() {
                    effects.append(Part(geometry: .path(d), color: Ink.blue, stroked: true,
                                        opacity: 0.75 + 0.25 * wave(0.8, Double(i) * 0.5)))
                }
            case .worried:
                for (i, d) in ["M98 42 L105 34", "M101 63 L112 62", "M98 86 L106 92"].enumerated() {
                    effects.append(Part(geometry: .path(d), color: Ink.coral, stroked: true,
                                        opacity: 0.7 + 0.3 * wave(0.7, Double(i) * 0.37)))
                }
            case .sleepy:
                effects.append(Part(geometry: .path("M90 30 L101 30 L90 41 L101 41"), color: Ink.blue, stroked: true))
                effects.append(Part(geometry: .path("M104 14 L112 14 L104 22 L112 22"), color: Ink.blue, stroked: true,
                                    opacity: 0.8))
            case .happy:
                break
            }
        }

        var all = body + effects
        if glyph {
            for i in all.indices { all[i].color = Ink.black; all[i].tilt = 0 }
        } else if stale {
            for i in all.indices { all[i].color = Ink.stale(all[i].color) }
        }
        return all
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

    /// The part's outline in design space, strokes already turned into fills.
    static func outline(_ part: Part) -> Path {
        var p: Path
        switch part.geometry {
        case let .rect(r, radius): p = Path(roundedRect: r, cornerRadius: radius, style: .circular)
        case let .circle(c, r): p = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        case let .path(d): p = path(d)
        }
        if part.tilt != 0 {
            p = p.applying(CGAffineTransform(translationX: pivot.x, y: pivot.y)
                .rotated(by: part.tilt * .pi / 180)
                .translatedBy(x: -pivot.x, y: -pivot.y))
        }
        return part.stroked ? p.strokedPath(StrokeStyle(lineWidth: part.width, lineCap: .round, lineJoin: .round)) : p
    }

    // MARK: SVG

    static func svg(_ mood: Mood, stale: Bool = false, glyph: Bool = false) -> String {
        let parts = parts(mood, stale: stale, glyph: glyph)
        let b = glyph ? glyphBox : box
        let name = glyph ? "menu-bar template, \(mood.rawValue)" : stale ? "stale data (\(mood.rawValue) in grey)" : mood.rawValue
        let size = glyph ? "width=\"\(n(18 * b.width / b.height))\" height=\"18\"" : "width=\"120\" height=\"120\""
        let note = glyph
            ? "Template image: one colour (black) plus a see-through face. macOS tints it for the menu bar."
            : """
            Palette: blue #008BE5, navy #004D80, coral #FD5C3F, face #002E4D, highlight #FFFFFF,
                 sleepy body #0072BD / #003D66, stale greys #8E99A3 #5E6A75 #A9B2BA #2F3A44.
            """
        var out = """
        <svg xmlns="http://www.w3.org/2000/svg" \(size) viewBox="\(n(b.minX)) \(n(b.minY)) \(n(b.width)) \(n(b.height))" fill="none">
        <title>Docket robot, \(name)</title>
        <!-- Generated from Shared/Robot.swift by the app's svg export. Edit the Swift, not this file.
             \(note) -->

        """
        let drawn = parts.filter { !$0.knockout }
        let cut = parts.filter(\.knockout)
        if !cut.isEmpty {
            out += "<defs><mask id=\"face\" maskUnits=\"userSpaceOnUse\" x=\"0\" y=\"0\" width=\"120\" height=\"120\">\n"
            out += "<rect width=\"120\" height=\"120\" fill=\"#FFFFFF\"/>\n"
            for var p in cut { p.color = 0; p.opacity = 1; out += element(p) }
            out += "</mask></defs>\n<g mask=\"url(#face)\">\n"
        }
        for p in drawn { out += element(p) }
        if !cut.isEmpty { out += "</g>\n" }
        return out + "</svg>\n"
    }

    private static func element(_ p: Part) -> String {
        let paint = p.stroked
            ? "stroke=\"\(hex(p.color))\" stroke-width=\"\(n(p.width))\" stroke-linecap=\"round\" stroke-linejoin=\"round\""
            : "fill=\"\(hex(p.color))\""
        var extra = p.opacity < 1 ? " opacity=\"\(n(p.opacity))\"" : ""
        if p.tilt != 0 { extra += " transform=\"rotate(\(n(p.tilt)) \(n(pivot.x)) \(n(pivot.y)))\"" }
        switch p.geometry {
        case let .rect(r, radius):
            return "<rect x=\"\(n(r.minX))\" y=\"\(n(r.minY))\" width=\"\(n(r.width))\" height=\"\(n(r.height))\" rx=\"\(n(radius))\" \(paint)\(extra)/>\n"
        case let .circle(c, r):
            return "<circle cx=\"\(n(c.x))\" cy=\"\(n(c.y))\" r=\"\(n(r))\" \(paint)\(extra)/>\n"
        case let .path(d):
            return "<path d=\"\(d)\" \(paint)\(extra)/>\n"
        }
    }

    private static func hex(_ c: UInt32) -> String { String(format: "#%06X", c) }

    private static func n(_ v: some BinaryFloatingPoint) -> String {
        let s = String(format: "%.2f", Double(v))
        return s.replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
    }
}

/// Whether robots animate (the app) or stay still (widgets, snapshots).
extension EnvironmentValues {
    @Entry var robotAnimates = false
}

/// The full-colour robot. Static unless `robotAnimates` is set and Reduce Motion is off.
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
        .accessibilityLabel(label ?? "Docket the robot, \(mood.label)")
    }
}

/// The one-colour menu-bar glyph: body and antenna in `color`, face cut out. Size it 18 pt tall.
struct RobotGlyph: View {
    var mood: Mood
    var color: Color = .black

    var body: some View {
        RobotParts(parts: Robot.parts(mood, glyph: true), box: Robot.glyphBox, tint: color)
            .aspectRatio(Robot.glyphBox.width / Robot.glyphBox.height, contentMode: .fit)
            .accessibilityElement()
            .accessibilityLabel("Docket, \(mood.label)")
    }
}

struct RobotParts: View {
    var parts: [Robot.Part]
    var box: CGRect
    var tint: Color? = nil

    var body: some View {
        ZStack {
            ForEach(parts.indices, id: \.self) { i in
                let part = parts[i]
                RobotPartShape(outline: Robot.outline(part), box: box)
                    .fill(tint ?? Color(hex: part.color))
                    .opacity(part.opacity)
                    .blendMode(part.knockout ? .destinationOut : .normal)
            }
        }
        .compositingGroup()
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
