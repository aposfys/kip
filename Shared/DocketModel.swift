import Foundation

enum Mood: String, CaseIterable, Identifiable {
    case happy, busy, worried, sleepy
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// Everything the views need, derived from the JSON and the clock.
struct DocketModel {
    var data: DocketData?
    var now: Date = .now
    /// Preview-only: the app's mood picker and the snapshot sheet force a face.
    var moodOverride: Mood? = nil

    static let staleAfter: TimeInterval = 26 * 3600
    static let iso = ISO8601DateFormatter()
    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }
    static func parse(_ stamp: String?) -> Date? { stamp.flatMap { iso.date(from: $0) } }

    var brief: DocketData.Brief? { data?.brief }
    var mac: DocketData.Mac? { data?.mac }

    var briefUpdated: Date? { Self.parse(brief?.updatedAt) }
    var macUpdated: Date? { Self.parse(mac?.updatedAt) }
    var isBriefStale: Bool { briefUpdated.map { now.timeIntervalSince($0) > Self.staleAfter } ?? true }
    var isMacStale: Bool { macUpdated.map { now.timeIntervalSince($0) > Self.staleAfter } ?? true }
    var isBriefForToday: Bool { brief?.date == Self.dayString(now) }

    var today: [DocketData.Item] { brief?.today ?? [] }
    var week: [DocketData.Item] { brief?.week ?? [] }
    var overdue: Int { brief?.overdueCount ?? 0 }
    var open: Int { brief?.openCount ?? 0 }
    var issues: [String] { mac?.issues ?? [] }
    var weekCount: Int { max(brief?.weekCount ?? 0, week.count) }
    var nextDeadline: DocketData.Item? { brief?.nextDeadline }

    /// "3 waiting · 4 no date", or nil when both are zero or missing.
    var laterLine: String? {
        let waiting = brief?.waitingCount ?? 0, nodate = brief?.nodateCount ?? 0
        let parts = [waiting > 0 ? "\(waiting) waiting" : nil, nodate > 0 ? "\(nodate) no date" : nil].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static let scanFreshFor: TimeInterval = 3 * 3600
    static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"
        return f
    }()

    var scan: DocketData.Scan? { data?.scan }
    var scanned: Date? { Self.parse(scan?.scannedAt) ?? Self.parse(scan?.updatedAt) }

    /// Agents working at the last scan. 0 once the scan is over 3 hours old, so an old count never shows.
    var agentsRunning: Int {
        guard let scanned, now.timeIntervalSince(scanned) <= Self.scanFreshFor else { return 0 }
        return scan?.agentsRunning ?? scan?.agents?.count ?? 0
    }

    var agentsSpoken: String {
        let titles = (scan?.agents ?? []).map(\.title).joined(separator: ", ")
        let count = agentsRunning == 1 ? "1 agent working" : "\(agentsRunning) agents working"
        return titles.isEmpty ? count : "\(count): \(titles)"
    }

    /// "Mail checked 14:05" today, "Mail checked Mon" on an older day.
    var mailChecked: String? {
        guard let scanned else { return nil }
        let when = Calendar.current.isDate(scanned, inSameDayAs: now)
            ? Self.timeFormatter.string(from: scanned) : scanned.formatted(.dateTime.weekday(.abbreviated))
        return "Mail checked \(when)"
    }

    var oneThing: String {
        if let t = brief?.oneThing?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        return brief == nil ? "Your morning brief lands here after 08:00." : "Nothing pressing. Enjoy the day."
    }

    /// sleepy 22:00–07:00, then worried (overdue or Mac issue), then busy (3+ due today), else happy.
    var mood: Mood {
        if let moodOverride { return moodOverride }
        let hour = Calendar.current.component(.hour, from: now)
        if hour >= 22 || hour < 7 { return .sleepy }
        if overdue > 0 || !issues.isEmpty { return .worried }
        if isBriefForToday && today.count >= 3 { return .busy }
        return .happy
    }

    var moodLine: String {
        switch mood {
        case .sleepy: "Resting till 07:00"
        case .worried: overdue > 0 ? "\(overdue) overdue" : (issues.first ?? "Something needs a look")
        case .busy: "\(today.count) things today"
        case .happy: "All calm"
        }
    }

    var robotLabel: String { "Docket the robot, \(mood.rawValue): \(moodLine)" }

    var ageText: String {
        guard let d = briefUpdated else { return "No brief" }
        let s = max(0, now.timeIntervalSince(d))
        if isBriefStale { return s >= 2 * 86400 ? "\(Int(s / 86400))d old" : "\(Int(s / 3600))h old" }
        switch s {
        case ..<60: return "now"
        case ..<3600: return "\(Int(s / 60))m ago"
        default: return "\(Int(s / 3600))h ago"
        }
    }

    var ageSpoken: String {
        guard let d = briefUpdated else { return "No brief yet" }
        let rel = RelativeDateTimeFormatter().localizedString(for: d, relativeTo: now)
        return isBriefStale ? "Brief out of date, updated \(rel)" : "Brief updated \(rel)"
    }

    /// The next 07:00 or 22:00, where the robot wakes up or falls asleep.
    static func nextBoundary(after date: Date, calendar: Calendar = .current) -> Date {
        [7, 22].compactMap {
            calendar.nextDate(after: date, matching: DateComponents(hour: $0, minute: 0), matchingPolicy: .nextTime)
        }.min() ?? date.addingTimeInterval(3600)
    }
}

/// Short due labels: "17:00", "today", "Tmrw 09:00", "Thu", "3 Dec", "2d late".
enum DueFormat {
    struct Label { var short: String; var spoken: String }

    static func format(_ raw: String?, now: Date, calendar: Calendar = .current) -> Label? {
        guard let raw = raw?.trimmingCharacters(in: .whitespaces), !raw.isEmpty else { return nil }
        if raw.count == 5, raw.dropFirst(2).first == ":" { return Label(short: raw, spoken: "at \(raw)") }
        guard let day = DocketModel.dayFormatter.date(from: String(raw.prefix(10))) else {
            return Label(short: raw, spoken: raw)
        }
        let rest = raw.dropFirst(10).trimmingCharacters(in: CharacterSet(charactersIn: " T"))
        let time = rest.count >= 5 ? String(rest.prefix(5)) : nil
        let t = time.map { " " + $0 } ?? ""
        let at = time.map { " at " + $0 } ?? ""
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: day)).day ?? 0
        switch days {
        case ..<0: return Label(short: "\(-days)d late", spoken: -days == 1 ? "1 day late" : "\(-days) days late")
        case 0: return Label(short: time ?? "today", spoken: "today" + at)
        case 1: return Label(short: "Tmrw" + t, spoken: "tomorrow" + at)
        case 2...6: return Label(short: day.formatted(.dateTime.weekday(.abbreviated)) + t,
                                 spoken: day.formatted(.dateTime.weekday(.wide)) + at)
        default:
            let d = day.formatted(.dateTime.day().month(.abbreviated))
            return Label(short: d, spoken: d)
        }
    }
}
