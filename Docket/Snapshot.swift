import AppKit
import SwiftUI

/// `kip --snapshot <dir>` writes docket-light.png and docket-dark.png (every mood, the stale
/// state and a crowded day, in all three sizes, from the real data file) and robot-moods.png.
/// `kip --svg <dir>` writes the robot's master SVGs (Design/robot in the repo).
/// `kip --companion-shot <dir>` writes the menu-bar popover's panes with sample content.
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
        // Six moods: the five Mood cases plus stale (old data), each as full art and a small menu-bar cut.
        let moods = Mood.allCases.map { ($0.rawValue, $0, false) } + [("stale", Mood.calm, true)]
        var files: [(String, String)] = []
        for (name, mood, stale) in moods {
            files.append(("kip-\(name).svg", Robot.svg(mood, stale: stale)))
            files.append(("kip-\(name)-small.svg", Robot.svg(mood, stale: stale, glyph: true)))
        }
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

    /// Through a real window, because ImageRenderer leaves text fields and pickers blank.
    static func companion(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = Date.now
        func store(_ tab: CompanionTab) -> CompanionStore {
            let s = CompanionStore()
            if s.data?.brief == nil { s.data = .sample }
            s.tab = tab
            return s
        }
        let today = store(.today)
        today.actionTitle = "Disk preview"
        today.actionResult = RunResult(ok: true, text: """
            ➤ User caches · 2.1 GB
            ➤ Xcode DerivedData · 6.4 GB
            ➤ Homebrew old versions · 830 MB
            Potential space: 9.3 GB (dry run, nothing removed)
            """)
        let ask = store(.ask)
        ask.question = "What should I do first this afternoon?"
        ask.answer = RunResult(ok: true, text: """
            Start with the PhD methods draft: it is due tomorrow and nothing else today is as close. \
            After that, reply to the two waiting emails. Your Mac is fine, with 120 GB free.
            """)
        let tasks = store(.tasks)
        tasks.tasks = [
            DocketTask(id: "0a1b2c3d", prompt: "Search the web for new papers on antimicrobial peptides and tell me the top 3",
                       engine: .agy, schedule: Schedule(kind: .weekly, weekdays: [1], hour: 9),
                       lastRun: now.addingTimeInterval(-26 * 3600), lastOK: true,
                       lastResult: "3 new papers: a cyclic AMP screen in Nature Comms, a review of membrane models, and a dataset."),
            DocketTask(id: "4e5f6a7b", prompt: "Tell me what is overdue and what is due tomorrow", engine: .claude,
                       schedule: Schedule(kind: .weekly, weekdays: [1, 2, 3, 4, 5], hour: 18),
                       lastRun: now.addingTimeInterval(-20 * 3600), lastOK: false,
                       lastResult: "Not logged in. Run claude in a terminal and sign in with /login."),
            DocketTask(id: "8c9d0e1f", prompt: "Check free disk space", engine: .claude,
                       schedule: Schedule(kind: .daily, hour: 8), paused: true),
        ]
        let editor = store(.ask)
        editor.question = "every Monday 9:00 check arXiv for AMP papers and tell me"
        if let parsed = TaskParser.parse(editor.question) {
            editor.draft = TaskDraft(task: DocketTask(id: "2a3b4c5d", prompt: parsed.prompt, engine: .agy, schedule: parsed.schedule),
                                     isNew: true, askText: editor.question)
        }
        for (name, s, dark) in [("today", today, false), ("today-dark", today, true), ("ask", ask, false),
                                ("tasks", tasks, false), ("task-editor", editor, false)] {
            window(CompanionView().environment(s), dark: dark, to: dir.appendingPathComponent("companion-\(name).png"))
        }
        for (mood, stale) in Mood.allCases.map({ ($0, false) }) + [(.calm, true)] {
            if let tiff = MenuIcon.image(mood, stale: stale).tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
               let png = rep.representation(using: .png, properties: [:]) {
                try? png.write(to: dir.appendingPathComponent("menubar-\(stale ? "stale" : mood.rawValue).png"))
            }
        }
    }

    private static func window(_ view: some View, dark: Bool, to url: URL) {
        let host = NSHostingView(rootView: view.background(dark ? Color(white: 0.17) : Color(white: 0.95)))
        host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let win = NSWindow(contentRect: host.frame, styleMask: .borderless, backing: .buffered, defer: false)
        win.appearance = host.appearance
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: .now.addingTimeInterval(0.3))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        do {
            try png.write(to: url)
            print(url.path)
        } catch {
            FileHandle.standardError.write(Data("snapshot: \(error.localizedDescription)\n".utf8))
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
            Text("kip, \(source), \(scheme == .dark ? "dark" : "light")")
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
    private let rows: [(String, Mood, Bool)] = Mood.allCases.map { ($0.label, $0, false) } + [("Stale", .calm, true)]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("kip: moods at 32, 44, 64 and 120 pt").font(.title3.bold())
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

    /// The colour menu-bar icon on a light and a dark bar, at 18 pt and doubled.
    private func glyphs(_ scheme: ColorScheme) -> some View {
        let ink: Color = scheme == .dark ? .white : .black
        return HStack(spacing: 16) {
            Text("Menu bar, \(scheme == .dark ? "dark" : "light")").font(.callout.weight(.medium))
            ForEach(rows, id: \.0) { row in
                HStack(spacing: 6) {
                    RobotGlyph(mood: row.1, stale: row.2).frame(height: 18)
                    RobotGlyph(mood: row.1, stale: row.2).frame(height: 36)
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

/// `kip --selftest`: the mood rules, stale cut-off, wake/sleep boundary and due labels.
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

        precondition(mood(noon) == .calm, "calm")
        precondition(DocketModel(data: d, now: noon).moodLine == "2 things today", "calm line")
        precondition(mood(at(23)) == .resting && mood(at(6)) == .resting, "resting")
        d.brief?.today = []
        precondition(mood(noon) == .happy && DocketModel(data: d, now: noon).moodLine == "Nothing due today", "happy")
        d.brief?.date = DocketModel.dayString(cal.date(byAdding: .day, value: -1, to: noon)!)
        precondition(mood(noon) == .calm, "an old brief is never happy")
        d.brief?.date = DocketModel.dayString(noon)
        d.brief?.today = [item, item, item]
        precondition(mood(noon) == .busy, "busy")
        d.brief?.overdueCount = 1
        precondition(mood(noon) == .worried, "worried: overdue")
        precondition(mood(at(23)) == .resting, "resting beats worried")
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
        let worried = Robot.svg(.worried)
        precondition(worried.contains("matrix(") && worried.contains("#FF3B30"), "worried jolts up, red ball")
        precondition(Robot.svg(.calm).contains("feTurbulence") && Robot.svg(.calm).contains("clipPath"), "pencil and hatching")
        let glyph = Robot.svg(.calm, glyph: true)
        precondition(!glyph.contains("filter") && !glyph.contains("clipPath") && glyph.contains("#5AB8FF"), "crisp colour glyph")
        let slab = Robot.path(Robot.slab(CGRect(x: 10, y: 61, width: 90, height: 36), radius: 17)).cgPath.boundingBoxOfPath
        precondition(abs(slab.minX - 10) < 0.5 && abs(slab.maxX - 100) < 0.5 && abs(slab.maxY - 97) < 0.6, "hand-traced slab")
        precondition(Robot.svg(.calm).contains("fill=\"#FF7A5C\"") && !Robot.svg(.calm, stale: true).contains("fill=\"#FF7A5C\""),
                     "blush on every mood but stale")
        let lifted = Robot.outline(Robot.parts(.busy)[4]).cgPath.boundingBoxOfPath, flat = Robot.outline(Robot.parts(.calm)[4]).cgPath.boundingBoxOfPath
        precondition(lifted.minY < flat.minY - 10 && abs(lifted.maxY - flat.maxY) < 3, "busy lifts its front, tail stays down")
        let suite = "kip-selftest-\(ProcessInfo.processInfo.processIdentifier)"
        if let defaults = UserDefaults(suiteName: suite) {
            let key = "NSStatusItem Preferred Position kip"
            StatusItemController.seedPosition(in: defaults)
            precondition(defaults.double(forKey: key) == 230 && defaults.bool(forKey: "NSStatusItem Visible kip"),
                         "status item: first launch seeds a visible position")
            defaults.set(512.0, forKey: key)
            StatusItemController.seedPosition(in: defaults)
            precondition(defaults.double(forKey: key) == 512, "status item: a saved position is kept")
            defaults.removePersistentDomain(forName: suite)
        }
        companion(noon: noon, at: at)
        print("selftest ok")
    }

    /// The companion's parser, schedules, launchd plist, id checks, alert dedupe and read-only flags.
    static func companion(noon: Date, at: (Int) -> Date) {
        func parsed(_ text: String) -> (kind: Schedule.Kind, days: [Int], day: Int, hour: Int, minute: Int, prompt: String)? {
            TaskParser.parse(text).map { ($0.schedule.kind, $0.schedule.weekdays, $0.schedule.monthDay,
                                          $0.schedule.hour, $0.schedule.minute, $0.prompt) }
        }
        let monday = parsed("every Monday 9:00 check X and tell me")
        precondition(monday?.kind == .weekly && monday?.days == [1] && monday?.hour == 9 && monday?.minute == 0
                     && monday?.prompt == "check X and tell me", "parse: every Monday 9:00")
        let weekday = parsed("every weekday at 8:30am summarise my overdue items")
        precondition(weekday?.days == [1, 2, 3, 4, 5] && weekday?.hour == 8 && weekday?.minute == 30
                     && weekday?.prompt == "summarise my overdue items", "parse: weekday 8:30am")
        let daily = parsed("every day at 6pm tell me what is due tomorrow")
        precondition(daily?.kind == .daily && daily?.hour == 18 && daily?.prompt == "tell me what is due tomorrow", "parse: 6pm")
        let hourly = parsed("every hour check the disk")
        precondition(hourly?.kind == .hourly && hourly?.prompt == "check the disk", "parse: hourly")
        let two = parsed("every mon and thu at 18:00 list open PhD tasks")
        precondition(two?.days == [1, 4] && two?.hour == 18 && two?.prompt == "list open PhD tasks", "parse: two days")
        let monthly = parsed("every month on the 3rd at 10 send me a recap")
        precondition(monthly?.kind == .monthly && monthly?.day == 3 && monthly?.hour == 10
                     && monthly?.prompt == "send me a recap", "parse: monthly")
        precondition(parsed("every evening at 7 remind me to stretch")?.hour == 19, "parse: evening at 7 is 19:00")
        precondition(parsed("every week on friday check 2 repos")?.days == [5], "parse: week on friday")
        precondition(parsed("every friday at 9 check 3 papers")?.hour == 9, "parse: later number stays in the prompt")
        precondition(parsed("what is due today") == nil && parsed("every Monday") == nil, "parse: not a task")

        let weekly = Schedule(kind: .weekly, weekdays: [5, 1], hour: 9)
        precondition(weekly.calendarIntervals == [["Weekday": 1, "Hour": 9, "Minute": 0], ["Weekday": 5, "Hour": 9, "Minute": 0]],
                     "intervals: weekly")
        precondition(Schedule(kind: .hourly, minute: 15).calendarIntervals == [["Minute": 15]], "intervals: hourly")
        precondition(weekly.summary == "Mondays, Fridays at 09:00" && Schedule(kind: .weekly, weekdays: [1, 2, 3, 4, 5]).summary
                     == "Weekdays at 09:00", "summary")
        let sunday = Schedule(kind: .weekly, weekdays: [7], hour: 9).next(after: noon)
        precondition(sunday.map { Calendar.current.component(.weekday, from: $0) } == 1, "next: Sunday")
        precondition(!Schedule(kind: .weekly, weekdays: []).isValid, "weekly needs a day")

        let task = DocketTask(id: "0a1b2c3d", prompt: "p", engine: .claude, schedule: weekly)
        let plist = TaskStore.plist(for: task, executable: "/Applications/kip.app/Contents/MacOS/kip")
        precondition(plist["Label"] as? String == "local.docket-task-0a1b2c3d", "plist label")
        precondition(plist["ProgramArguments"] as? [String] == ["/Applications/kip.app/Contents/MacOS/kip", "--run-task", "0a1b2c3d"],
                     "plist arguments")
        precondition((plist["StartCalendarInterval"] as? [[String: Int]])?.count == 2, "plist intervals")
        precondition((try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)) != nil, "plist serialises")

        precondition(DocketTask.isValidID(DocketTask.newID()), "new id is valid")
        precondition(!DocketTask.isValidID("../x") && !DocketTask.isValidID("ABCDEF12") && !DocketTask.isValidID("٠١٢٣٤٥٦٧"), "bad ids")
        precondition(TaskStore.load("../../etc") == nil, "load refuses paths")

        let suite = "docket-selftest"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        var a = DocketData.sample
        a.brief?.date = DocketModel.dayString(noon)
        a.brief?.overdueCount = 2
        func alert(_ now: Date) -> String? { Alerts.check(DocketModel(data: a, now: now), defaults: defaults) }
        precondition(alert(noon)?.hasPrefix("2 tasks are overdue.") == true, "alert: posts")
        precondition(alert(noon.addingTimeInterval(60)) == nil, "alert: dedupes")
        a.brief?.overdueCount = 3
        precondition(alert(at(23)) == nil, "alert: quiet at night")
        precondition(alert(noon) != nil, "alert: new count posts")
        a.brief?.overdueCount = 0
        precondition(alert(noon) == nil, "alert: nothing overdue")
        a.brief?.overdueCount = 3
        precondition(alert(noon) != nil, "alert: re-arms after clearing")

        precondition(Engine.guess("search the web for new AMP papers") == .agy && Engine.guess("what is due today") == .claude,
                     "engine guess")
        let args = Runner.claudeArgs()
        precondition(args.contains("--safe-mode") && args.contains("Read,Grep,Glob") && args.contains("sonnet"), "claude args")
        precondition(!args.joined(separator: " ").contains("Bash") && !args.contains { $0.contains("Edit") || $0.contains("Write") },
                     "claude is read-only")
    }
}
