import AppKit
import SwiftUI

/// `Docket --snapshot <dir>` writes docket-light.png and docket-dark.png (every mood, the stale
/// state and a crowded day, in all three sizes, from the real data file) and robot-moods.png.
/// `Docket --svg <dir>` writes the robot's master SVGs (Design/robot in the repo).
@MainActor
enum Snapshot {
    static func write(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let live = DocketStore.load()
        var data = live ?? .sample
        if data.brief == nil { data.brief = DocketData.sample.brief }  // before the first morning brief
        if data.scan == nil { data.scan = DocketData.sample.scan }  // before the first inbox scan write
        let source = live == nil ? "sample data"
            : live?.brief == nil || live?.scan == nil ? "live Mac data, sample brief and scan" : "live data"
        for scheme in [ColorScheme.light, .dark] {
            png(SnapshotSheet(data: data, source: source, scheme: scheme).environment(\.colorScheme, scheme),
                to: dir.appendingPathComponent("docket-\(scheme == .dark ? "dark" : "light").png"))
        }
        png(MoodSheet(), to: dir.appendingPathComponent("robot-moods.png"))
    }

    static func writeSVGs(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var files: [(String, String)] = Mood.allCases.map { ("\($0.rawValue).svg", Robot.svg($0)) }
        files.append(("stale.svg", Robot.svg(.happy, stale: true)))
        files += Mood.allCases.map { ("menubar-\($0.rawValue).svg", Robot.svg($0, glyph: true)) }
        for (name, svg) in files {
            let url = dir.appendingPathComponent(name)
            do {
                try svg.write(to: url, atomically: true, encoding: .utf8)
                print(url.path)
            } catch {
                FileHandle.standardError.write(Data("svg: \(error.localizedDescription)\n".utf8))
            }
        }
    }

    private static func png(_ view: some View, to url: URL) {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: url)
            print(url.path)
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error.localizedDescription)\n".utf8))
        }
    }

    /// A crowded day for checking clipping: 6 today, 7 of 14 this week, a Mac issue, 2 overdue, a long one thing,
    /// a long deadline, waiting and no-date counts and 3 agents.
    static func crowded(_ data: DocketData, now: Date) -> DocketData {
        var d = data
        let late = DocketModel.dayString(Calendar.current.date(byAdding: .day, value: -2, to: now)!)
        let titles = ["Chapter 2 draft to supervisor, with all figures", "Sprint review notes", "Reply to lab about MIC assay",
                      "MIC results write-up", "Design crit: onboarding flow", "Pay electricity bill", "Book conference flights"]
        let tags = ["phd", "work", "phd", "phd", "work", "personal", "personal"]
        d.brief?.oneThing = "Send the chapter 2 draft to your supervisor before Friday's lab meeting, with the new MIC figures"
        d.brief?.today = (0..<6).map { DocketData.Item(title: titles[$0], tag: tags[$0], due: $0 == 0 ? late : "17:00") }
        d.brief?.week = (0..<7).map { DocketData.Item(title: titles[6 - $0], tag: tags[6 - $0], due: nil) }
        d.brief?.overdueCount = 2
        d.brief?.weekCount = 14
        d.brief?.waitingCount = 6
        d.brief?.nodateCount = 11
        d.brief?.nextDeadline = DocketData.Item(title: "Ethics amendment for the second MIC study, signed by all",
                                                tag: "phd", due: DocketModel.dayString(now.addingTimeInterval(12 * 86400)))
        d.scan?.scannedAt = DocketModel.iso.string(from: now)
        d.scan?.agentsRunning = 3
        if d.mac == nil { d.mac = DocketData.sample.mac }
        d.mac?.issues = ["Disk almost full: 14 GB free"]
        return d
    }
}

struct SnapshotSheet: View {
    var data: DocketData
    var source: String
    var scheme: ColorScheme

    var body: some View {
        let now = Date.now
        let rows: [(String, DocketModel)] =
            Mood.allCases.map { ($0.label, DocketModel(data: data, now: now, moodOverride: $0)) }
            + [("Stale (seen 48h later)", DocketModel(data: data, now: now.addingTimeInterval(48 * 3600))),
               ("Crowded day (clipping check)", DocketModel(data: Snapshot.crowded(data, now: now), now: now))]
        VStack(alignment: .leading, spacing: 18) {
            Text("Docket, \(source), \(scheme == .dark ? "dark" : "light")")
                .font(.title3.bold())
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                VStack(alignment: .leading, spacing: 8) {
                    Text(row.0).font(.headline).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 18) {
                        ForEach(DocketFamily.allCases) { WidgetPreview(model: row.1, family: $0) }
                    }
                }
            }
        }
        .padding(28)
        .background(scheme == .dark ? Color(white: 0.07) : Color(white: 0.9))
    }
}

/// Every mood at 32, 44, 64 and 120 pt: colour on light and dark cards, grayscale, and the menu-bar glyph.
struct MoodSheet: View {
    private let sizes: [CGFloat] = [32, 44, 64, 120]
    private let rows: [(String, Mood, Bool)] = Mood.allCases.map { ($0.label, $0, false) } + [("Stale", .happy, true)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Docket robot: moods at 32, 44, 64 and 120 pt").font(.title3.bold())
            HStack(alignment: .top, spacing: 18) {
                panel("Colour, light card", scheme: .light)
                panel("Colour, dark card", scheme: .dark)
                panel("Grayscale", scheme: .light).grayscale(1)
            }
            HStack(spacing: 18) {
                glyphs(.light)
                glyphs(.dark)
            }
        }
        .padding(28)
        .background(Color(white: 0.9))
        .environment(\.colorScheme, .light)
    }

    private func panel(_ title: String, scheme: ColorScheme) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            ForEach(rows, id: \.0) { row in
                HStack(alignment: .bottom, spacing: 14) {
                    Text(row.0).font(.callout.weight(.medium)).frame(width: 64, alignment: .leading)
                    ForEach(sizes, id: \.self) { RobotView(mood: row.1, stale: row.2).frame(width: $0, height: $0) }
                }
            }
        }
        .foregroundStyle(scheme == .dark ? Color.white : Color.black)
        .padding(16)
        .background(DocketBackground().environment(\.colorScheme, scheme))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    /// The template glyph the way the menu bar tints it: black on a light bar, white on a dark one.
    private func glyphs(_ scheme: ColorScheme) -> some View {
        let ink: Color = scheme == .dark ? .white : .black
        return HStack(spacing: 16) {
            Text("Menu bar, \(scheme == .dark ? "dark" : "light")").font(.callout.weight(.medium))
            ForEach(Mood.allCases) { mood in
                HStack(spacing: 6) {
                    RobotGlyph(mood: mood, color: ink).frame(height: 18)
                    RobotGlyph(mood: mood, color: ink).frame(height: 36)
                }
            }
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

/// `Docket --selftest`: the mood rules, stale cut-off, wake/sleep boundary and due labels.
enum SelfTest {
    static func run() {
        let cal = Calendar.current
        func at(_ hour: Int) -> Date { cal.date(bySettingHour: hour, minute: 0, second: 0, of: .now)! }
        let noon = at(12)
        let item = DocketData.Item(title: "x", tag: nil, due: nil)
        var d = DocketData.sample
        d.brief?.updatedAt = DocketModel.iso.string(from: at(8))
        d.brief?.date = DocketModel.dayString(noon)
        d.brief?.overdueCount = 0
        d.brief?.today = [item, item]
        d.mac?.issues = []
        func mood(_ now: Date) -> Mood { DocketModel(data: d, now: now).mood }

        precondition(mood(noon) == .happy, "happy")
        precondition(mood(at(23)) == .sleepy && mood(at(6)) == .sleepy, "sleepy")
        d.brief?.today = [item, item, item]
        precondition(mood(noon) == .busy, "busy")
        d.brief?.overdueCount = 1
        precondition(mood(noon) == .worried, "worried: overdue")
        precondition(mood(at(23)) == .sleepy, "sleepy beats worried")
        d.brief?.overdueCount = 0
        d.mac?.issues = ["Disk low"]
        precondition(mood(noon) == .worried, "worried: mac issue")

        precondition(!DocketModel(data: d, now: noon).isBriefStale, "fresh")
        precondition(DocketModel(data: d, now: at(8).addingTimeInterval(27 * 3600)).isBriefStale, "stale")
        precondition(DocketModel(data: nil).isBriefStale, "no data is stale")
        precondition(cal.component(.hour, from: DocketModel.nextBoundary(after: noon)) == 22, "boundary 22")
        precondition(cal.component(.hour, from: DocketModel.nextBoundary(after: at(23))) == 7, "boundary 07")

        let today = DocketModel.dayString(noon)
        let yesterday = DocketModel.dayString(cal.date(byAdding: .day, value: -2, to: noon)!)
        precondition(DueFormat.format("\(today) 17:00", now: noon)?.short == "17:00", "due time")
        precondition(DueFormat.format(today, now: noon)?.short == "today", "due today")
        precondition(DueFormat.format(yesterday, now: noon)?.short == "2d late", "due late")
        precondition(DueFormat.format("09:30", now: noon)?.short == "09:30", "bare time")
        precondition(DocketStore.decode(Data(#"{"brief":{"one_thing":"a","overdue_count":2}}"#.utf8))?.brief?.overdueCount == 2,
                     "snake_case decode")
        precondition(DocketCard.limit(3, rows: 4, cap: 4) == 3 && DocketCard.limit(6, rows: 4, cap: 4) == 3,
                     "row budget: today")
        precondition(DocketCard.limit(7, rows: 2, cap: 5) == 1 && DocketCard.limit(5, rows: 6, cap: 5) == 5, "row budget: week")
        let extra = DocketStore.decode(Data(#"""
            {"brief":{"week_count":14,"waiting_count":3,"nodate_count":0,"next_deadline":{"title":"Report","due":"2026-12-01"}},
             "scan":{"scanned_at":"2026-11-22T14:05:00+02:00","agents_running":2,"agents":[{"title":"A"}]}}
            """#.utf8))
        precondition(extra?.brief?.nextDeadline?.title == "Report" && extra?.scan?.agentsRunning == 2, "new keys decode")
        var m = DocketModel(data: extra, now: DocketModel.parse("2026-11-22T14:35:00+02:00")!)
        precondition(m.laterLine == "3 waiting" && m.weekCount == 14 && m.agentsRunning == 2, "counts and agents")
        m.now = m.now.addingTimeInterval(4 * 3600)
        precondition(m.agentsRunning == 0, "old scan hides agents")
        let box = Robot.path("M10 20 L30 20 C30 30 30 40 10 40 Q0 30 10 20 Z").boundingRect
        precondition(box.minX >= 0 && box.minY == 20 && box.maxX == 30 && box.maxY == 40, "svg path parser")
        precondition(Robot.svg(.worried).contains("rotate(-5 58 76)"), "worried lean")
        precondition(!Robot.svg(.happy, glyph: true).contains("#008BE5"), "glyph is one colour")
        print("selftest ok")
    }
}
