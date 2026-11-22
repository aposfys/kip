import Foundation

/// A recurring prompt, like a Grok task: runs on a schedule, posts the answer as a notification and logs it.
struct DocketTask: Codable, Identifiable, Equatable {
    var id: String
    var prompt: String
    var engine: Engine
    var schedule: Schedule
    var paused = false
    var created = Date.now
    var lastRun: Date?
    var lastOK: Bool?
    var lastResult: String?

    static func newID() -> String { String(UUID().uuidString.lowercased().filter(\.isHexDigit).prefix(8)) }

    /// Ids come back from the command line and become file names, so only 8 hex characters pass.
    static func isValidID(_ id: String) -> Bool {
        id.count == 8 && id.allSatisfy { ("0"..."9").contains($0) || ("a"..."f").contains($0) }
    }

    var title: String {
        let line = prompt.split(separator: "\n").first.map(String.init) ?? prompt
        return line.count > 48 ? String(line.prefix(47)) + "…" : line
    }
}

struct Schedule: Codable, Equatable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case hourly, daily, weekly, monthly
        var id: String { rawValue }
        var label: String { rawValue.capitalized }
    }

    var kind: Kind
    /// 1 = Monday … 7 = Sunday. launchd reads 7 as Sunday too.
    var weekdays: [Int] = []
    var monthDay = 1
    var hour = 9
    var minute = 0

    static let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let fullDayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]

    var time: String { String(format: "%02d:%02d", hour, minute) }

    var summary: String {
        switch kind {
        case .hourly: return String(format: "Every hour at :%02d", minute)
        case .daily: return "Every day at \(time)"
        case .weekly:
            let days = weekdays.sorted()
            let names = days == [1, 2, 3, 4, 5] ? "Weekdays" : days == [6, 7] ? "Weekends"
                : days.count == 7 ? "Every day" : days.map { Self.fullDayNames[$0 - 1] + "s" }.joined(separator: ", ")
            return "\(names.isEmpty ? "No days" : names) at \(time)"
        case .monthly: return "Day \(monthDay) of each month at \(time)"
        }
    }

    /// launchd's StartCalendarInterval entries.
    var calendarIntervals: [[String: Int]] {
        switch kind {
        case .hourly: return [["Minute": minute]]
        case .daily: return [["Hour": hour, "Minute": minute]]
        case .weekly: return weekdays.sorted().map { ["Weekday": $0, "Hour": hour, "Minute": minute] }
        case .monthly: return [["Day": monthDay, "Hour": hour, "Minute": minute]]
        }
    }

    var isValid: Bool {
        (0...59).contains(minute) && (0...23).contains(hour) && (1...28).contains(monthDay)
            && (kind != .weekly || (!weekdays.isEmpty && weekdays.allSatisfy { (1...7).contains($0) }))
    }

    func next(after date: Date, calendar: Calendar = .current) -> Date? {
        calendarIntervals.compactMap { entry -> Date? in
            var c = DateComponents()
            c.minute = entry["Minute"]
            c.hour = entry["Hour"]
            c.day = entry["Day"]
            c.weekday = entry["Weekday"].map { $0 % 7 + 1 }  // Foundation: 1 = Sunday
            return calendar.nextDate(after: date, matching: c, matchingPolicy: .nextTime)
        }.min()
    }
}

/// "every Monday 9:00 check X and tell me" into a schedule and the prompt that follows it.
/// shortcut: English only and a fixed word list; add phrasings here as they come up.
enum TaskParser {
    private static let days: [String: Int] = [
        "monday": 1, "mon": 1, "tuesday": 2, "tue": 2, "tues": 2, "wednesday": 3, "wed": 3,
        "thursday": 4, "thu": 4, "thur": 4, "thurs": 4, "friday": 5, "fri": 5, "saturday": 6, "sat": 6,
        "sunday": 7, "sun": 7,
    ]
    private static let partsOfDay: [String: Int] = ["morning": 9, "noon": 12, "midday": 12, "afternoon": 15,
                                                    "evening": 18, "night": 21, "tonight": 21]
    private static let filler: Set<String> = ["every", "each", "on", "at", "and", "the", "in", "of", "a", ",", "&", "o'clock"]

    static func parse(_ text: String) -> (schedule: Schedule, prompt: String)? {
        let words = text.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first?.lowercased(),
              ["every", "each", "daily", "hourly", "weekly", "monthly"].contains(first) else { return nil }

        var kind: Schedule.Kind?
        var weekdays: Set<Int> = []
        var hour: Int?, dayPart: Int?, minute = 0, monthDay: Int?
        var pm: Bool?
        var used = 0

        for word in words {
            let w = word.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ",.;:!"))
            let bare = w.hasSuffix("s") && days[String(w.dropLast())] != nil ? String(w.dropLast()) : w
            if filler.contains(w) || w.isEmpty {
            } else if w == "day" || w == "days" || w == "daily" {
                kind = kind ?? .daily
            } else if w == "hour" || w == "hourly" {
                kind = .hourly
            } else if w == "week" || w == "weekly" {
                kind = kind ?? .weekly
            } else if w == "month" || w == "monthly" {
                kind = .monthly
            } else if w == "weekday" || w == "weekdays" || w == "workday" || w == "workdays" {
                kind = .weekly
                weekdays.formUnion(1...5)
            } else if w == "weekend" || w == "weekends" {
                kind = .weekly
                weekdays.formUnion([6, 7])
            } else if let d = days[bare] {
                kind = .weekly
                weekdays.insert(d)
            } else if let h = partsOfDay[w] {
                kind = kind ?? .daily
                dayPart = dayPart ?? h
            } else if w == "am" || w == "pm" {
                pm = w == "pm"
            } else if hour == nil, let t = clock(w) {  // one time only, so a number in the prompt stays there
                hour = t.hour
                minute = t.minute
                pm = t.pm ?? pm
            } else if let n = ordinal(w) {
                monthDay = n
                kind = kind ?? .monthly
            } else {
                break
            }
            used += 1
        }

        guard var kind else { return nil }
        if kind == .weekly && weekdays.count == 7 { kind = .daily }
        if kind == .weekly && weekdays.isEmpty { weekdays = [1] }  // "every week": Mondays
        if let p = pm, var h = hour {
            if p && h < 12 { h += 12 }
            if !p && h == 12 { h = 0 }
            hour = h
        } else if pm == nil, let part = dayPart, part >= 15, let h = hour, h < 12 {
            hour = h + 12  // "every evening at 7" is 19:00
        }
        hour = hour ?? dayPart
        let prompt = words.dropFirst(used).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: ",;:- ").union(.whitespaces))
        let cleaned = prompt.lowercased().hasPrefix("to ") ? String(prompt.dropFirst(3)) : prompt
        guard !cleaned.isEmpty else { return nil }
        let schedule = Schedule(kind: kind, weekdays: weekdays.sorted(), monthDay: min(max(monthDay ?? 1, 1), 28),
                                hour: min(hour ?? 9, 23), minute: min(minute, 59))
        return (schedule, cleaned)
    }

    /// "9:00", "9", "18:30", "9am", "6.30pm".
    private static func clock(_ w: String) -> (hour: Int, minute: Int, pm: Bool?)? {
        var s = Substring(w)
        var pm: Bool?
        if s.hasSuffix("am") || s.hasSuffix("pm") {
            pm = s.hasSuffix("pm")
            s = s.dropLast(2)
        }
        let parts = s.split(omittingEmptySubsequences: false, whereSeparator: { $0 == ":" || $0 == "." })
        guard (1...2).contains(parts.count), let h = Int(parts[0]), (0...23).contains(h) else { return nil }
        let m = parts.count == 2 ? Int(parts[1]) : 0
        guard let m, (0...59).contains(m), parts.count == 2 || pm != nil || parts[0].count <= 2 else { return nil }
        return (h, m, pm)
    }

    /// "1st", "3rd", "15th".
    private static func ordinal(_ w: String) -> Int? {
        guard ["st", "nd", "rd", "th"].contains(where: w.hasSuffix), let n = Int(w.dropLast(2)), (1...31).contains(n)
        else { return nil }
        return n
    }
}

/// Tasks live as JSON in ~/.claude/docket/tasks/<id>.json with a <id>.log beside each. A LaunchAgent per
/// active task runs `kip --run-task <id>`; pausing removes the agent and keeps the JSON.
enum TaskStore {
    static let dir = Runner.docketDir.appendingPathComponent("tasks")
    static let agentsDir = Runner.home.appendingPathComponent("Library/LaunchAgents")

    static func label(_ id: String) -> String { "local.docket-task-\(id)" }
    static func plistURL(_ id: String) -> URL { agentsDir.appendingPathComponent("\(label(id)).plist") }
    static func jsonURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).json") }
    static func logURL(_ id: String) -> URL { dir.appendingPathComponent("\(id).log") }

    private static var encoder: JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    private static var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    static func all() -> [DocketTask] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { try? decoder.decode(DocketTask.self, from: Data(contentsOf: $0)) }
            .sorted { $0.created < $1.created }
    }

    static func load(_ id: String) -> DocketTask? {
        guard DocketTask.isValidID(id) else { return nil }
        return try? decoder.decode(DocketTask.self, from: Data(contentsOf: jsonURL(id)))
    }

    static func write(_ task: DocketTask) throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try encoder.encode(task).write(to: jsonURL(task.id), options: .atomic)
    }

    /// Saves the task and loads or removes its LaunchAgent to match `paused`.
    static func save(_ task: DocketTask, executable: String = Bundle.main.executablePath ?? "") throws {
        guard DocketTask.isValidID(task.id), task.schedule.isValid else { throw TaskError.invalid }
        try write(task)
        if task.paused { unload(task.id) } else { try install(task, executable: executable) }
    }

    /// Removes the agent, the JSON and the log. The UI asks first.
    static func delete(_ id: String) {
        guard DocketTask.isValidID(id) else { return }
        unload(id)
        try? FileManager.default.removeItem(at: jsonURL(id))
        try? FileManager.default.removeItem(at: logURL(id))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("\(id).err"))
    }

    static func plist(for task: DocketTask, executable: String) -> [String: Any] {
        let intervals = task.schedule.calendarIntervals
        return [
            "Label": label(task.id),
            "ProgramArguments": [executable, "--run-task", task.id],
            "StartCalendarInterval": intervals.count == 1 ? intervals[0] as Any : intervals as Any,
            "StandardErrorPath": dir.appendingPathComponent("\(task.id).err").path,
        ]
    }

    static func install(_ task: DocketTask, executable: String) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist(for: task, executable: executable),
                                                      format: .xml, options: 0)
        try FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try data.write(to: plistURL(task.id), options: .atomic)
        launchctl(["bootout", "gui/\(getuid())/\(label(task.id))"])
        guard launchctl(["bootstrap", "gui/\(getuid())", plistURL(task.id).path]) else { throw TaskError.launchd }
    }

    static func unload(_ id: String) {
        launchctl(["bootout", "gui/\(getuid())/\(label(id))"])
        try? FileManager.default.removeItem(at: plistURL(id))
    }

    /// Points every active task's agent at this copy of the app, in case it moved since the task was saved.
    /// shortcut: running a build-folder copy repoints them there; launch the installed app again to fix.
    static func syncAgents() {
        guard let exe = Bundle.main.executablePath else { return }
        for task in all() where !task.paused {
            let current = NSDictionary(contentsOf: plistURL(task.id))?["ProgramArguments"] as? [String]
            if current?.first != exe { try? install(task, executable: exe) }
        }
    }

    @discardableResult
    private static func launchctl(_ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    /// shortcut: the log only grows; trim it by hand if it ever matters (entries are under 1 KB).
    static func appendLog(_ id: String, at date: Date, result: RunResult) {
        let entry = "\(DocketModel.iso.string(from: date)) \(result.ok ? "ok" : "failed")\n\(result.text)\n---\n"
        if let h = try? FileHandle(forWritingTo: logURL(id)) {
            h.seekToEndOfFile()
            h.write(Data(entry.utf8))
            try? h.close()
        } else {
            try? Data(entry.utf8).write(to: logURL(id))
        }
    }

    /// `kip --run-task <id>`: the LaunchAgent's entry point, and Run now's. Returns the exit code.
    static func runHeadless(_ id: String) -> Int32 {
        guard let task = load(id) else { return 2 }
        let started = Date.now
        let result = Runner.ask(task.prompt, engine: task.engine)
        // Re-read before writing, so an edit made while this ran is kept and a delete stays deleted.
        if var latest = load(id) {
            latest.lastRun = started
            latest.lastOK = result.ok
            latest.lastResult = String(result.text.prefix(2000))
            try? write(latest)
            appendLog(id, at: started, result: result)
        }
        Notifier.postAndWait(id: "task-\(id)-\(Int(started.timeIntervalSince1970))",
                             title: result.ok ? task.title : "Task failed: \(task.title)", body: result.text)
        return result.ok ? 0 : 1
    }

    enum TaskError: LocalizedError {
        case invalid, launchd
        var errorDescription: String? {
            self == .invalid ? "The schedule is not complete." : "launchd did not accept the task."
        }
    }
}
