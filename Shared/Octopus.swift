import SwiftUI
import WidgetKit

/// A path drawn in a 100×100 design space, scaled to fit and centred.
struct Sketch: Shape {
    var draw: @Sendable (inout Path) -> Void

    func path(in rect: CGRect) -> Path {
        var p = Path()
        draw(&p)
        let s = min(rect.width, rect.height) / 100
        return p.applying(CGAffineTransform(a: s, b: 0, c: 0, d: s,
                                            tx: rect.midX - 50 * s, ty: rect.midY - 50 * s))
    }
}

private func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }

private func oval(_ p: inout Path, _ cx: CGFloat, _ cy: CGFloat, _ w: CGFloat, _ h: CGFloat) {
    p.addEllipse(in: CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h))
}

/// Aori, the Docket octopus: plain vector shapes, one face per mood.
struct Octopus: View {
    var mood: Mood
    var label: String
    @Environment(\.colorScheme) private var scheme

    private nonisolated static let eyeX: [CGFloat] = [41, 59]

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height) / 100
            let skin = scheme == .dark ? Palette.scarlet : Palette.terracotta
            ZStack {
                Group {
                    Sketch(draw: Self.tentacles)
                        .stroke(skin, style: StrokeStyle(lineWidth: 7.5 * s, lineCap: .round, lineJoin: .round))
                    Sketch(draw: Self.mantle).fill(skin)
                }
                .widgetAccentable()
                Sketch(draw: Self.spots).fill(Palette.rust.opacity(0.45))
                Sketch { oval(&$0, 36, 23, 10, 6) }.fill(.white.opacity(0.35))
                if mood != .worried {
                    Sketch { p in oval(&p, 32, 46, 8, 4.5); oval(&p, 68, 46, 8, 4.5) }
                        .fill(Palette.cheek.opacity(0.75))
                }
                face(s)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
    }

    @ViewBuilder private func face(_ s: CGFloat) -> some View {
        let line = StrokeStyle(lineWidth: 2.4 * s, lineCap: .round, lineJoin: .round)
        switch mood {
        case .happy:
            eyes(w: 7, h: 9)
            Sketch { p in
                p.move(to: pt(45, 49)); p.addQuadCurve(to: pt(55, 49), control: pt(50, 55))
            }.stroke(Palette.ink, style: line)
        case .busy:
            eyes(w: 7, h: 7.5)
            Sketch { p in
                p.move(to: pt(36.5, 29)); p.addLine(to: pt(44.5, 31.2))
                p.move(to: pt(63.5, 29)); p.addLine(to: pt(55.5, 31.2))
                p.move(to: pt(46.5, 50)); p.addLine(to: pt(53.5, 50))
            }.stroke(Palette.ink, style: line)
            Sketch(draw: Self.drop).fill(scheme == .dark ? Palette.shallow : Palette.aegean)
        case .worried:
            eyes(w: 8, h: 10)
            Sketch { p in
                p.move(to: pt(35.5, 30.5)); p.addLine(to: pt(44, 28))
                p.move(to: pt(64.5, 30.5)); p.addLine(to: pt(56, 28))
                p.move(to: pt(44, 51))
                p.addCurve(to: pt(56, 51), control1: pt(47, 47.5), control2: pt(53, 54.5))
            }.stroke(Palette.ink, style: line)
        case .sleepy:
            Sketch { p in
                for x in Self.eyeX {
                    p.move(to: pt(x - 4, 37)); p.addQuadCurve(to: pt(x + 4, 37), control: pt(x, 41.5))
                }
                oval(&p, 50, 50.5, 3.6, 3.6)
            }.stroke(Palette.ink, style: line)
            ZStack {
                Text("z").font(.system(size: 14 * s, weight: .heavy, design: .rounded))
                    .position(x: 79 * s, y: 24 * s)
                Text("Z").font(.system(size: 20 * s, weight: .heavy, design: .rounded))
                    .position(x: 90 * s, y: 11 * s)
            }
            .foregroundStyle(Color.primary.opacity(0.55))
        }
    }

    private func eyes(w: CGFloat, h: CGFloat) -> some View {
        ZStack {
            Sketch { p in for x in Self.eyeX { oval(&p, x, 37, w, h) } }.fill(Palette.ink)
            Sketch { p in for x in Self.eyeX { oval(&p, x + w * 0.2, 37 - h * 0.22, 2.8, 2.8) } }.fill(.white)
        }
    }

    private nonisolated static let tentacles: @Sendable (inout Path) -> Void = { p in
        let xs: [CGFloat] = [26, 35, 44, 56, 65, 74]
        let os: [CGFloat] = [-1.5, -0.9, -0.35, 0.35, 0.9, 1.5]
        for (x, o) in zip(xs, os) {
            p.move(to: pt(x, 54))
            p.addCurve(to: pt(x + o * 7, 82), control1: pt(x - o * 2, 66), control2: pt(x + o, 78))
            p.addQuadCurve(to: pt(x + o * 13, 78), control: pt(x + o * 12, 87))
        }
    }

    private nonisolated static let mantle: @Sendable (inout Path) -> Void = { p in
        p.move(to: pt(20, 58))
        p.addCurve(to: pt(50, 11), control1: pt(15, 30), control2: pt(31, 11))
        p.addCurve(to: pt(80, 58), control1: pt(69, 11), control2: pt(85, 30))
        p.addQuadCurve(to: pt(20, 58), control: pt(50, 67))
        p.closeSubpath()
    }

    /// Minoan-style spots on the mantle.
    private nonisolated static let spots: @Sendable (inout Path) -> Void = { p in
        let dots: [(CGFloat, CGFloat, CGFloat)] = [(53, 18, 2.2), (62, 23, 1.8), (45, 15.5, 1.4), (68, 30, 1.4)]
        for (x, y, r) in dots { oval(&p, x, y, r * 2, r * 2) }
    }

    private nonisolated static let drop: @Sendable (inout Path) -> Void = { p in
        p.move(to: pt(85, 19))
        p.addCurve(to: pt(85, 31), control1: pt(88.5, 25), control2: pt(89, 31))
        p.addCurve(to: pt(85, 19), control1: pt(81, 31), control2: pt(81.5, 25))
    }
}
