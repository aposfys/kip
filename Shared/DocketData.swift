import Foundation
import Security

/// The one local file the widget reads. Writers: ~/.claude/scripts/docket-widget-write.py
/// (hourly `mac` part from pc-health.sh, daily `brief` part from the morning brief task,
/// hourly `scan` part from the inbox scan task).
struct DocketData: Codable, Equatable {
    var updatedAt: String?
    var mac: Mac?
    var brief: Brief?
    var scan: Scan?

    struct Mac: Codable, Equatable {
        var updatedAt: String?
        var batteryPct: Int?
        var batteryHealthPct: Int?
        var cycles: Int?
        var thermal: String?
        var memFreePct: Int?
        var diskFreeGb: Double?
        var diskTotalGb: Double?
        var issues: [String]?
    }

    struct Brief: Codable, Equatable {
        var updatedAt: String?
        var date: String?
        var oneThing: String?
        var today: [Item]?
        var week: [Item]?
        var overdueCount: Int?
        var openCount: Int?
        /// All tasks due this week; `week` holds only the first 10.
        var weekCount: Int?
        var waitingCount: Int?
        var nodateCount: Int?
        /// The next PhD or personal deadline, which may be weeks away.
        var nextDeadline: Item?
    }

    struct Item: Codable, Equatable, Hashable {
        var title: String
        var tag: String?
        var due: String?
    }

    /// What the hourly inbox scan saw: when mail was last checked and which agents were working.
    struct Scan: Codable, Equatable {
        var updatedAt: String?
        var scannedAt: String?
        var agentsRunning: Int?
        var agents: [Agent]?
    }

    struct Agent: Codable, Equatable, Hashable {
        var title: String
        var project: String?
    }
}

enum DocketLinks {
    static let inbox = URL(string: "https://claude.ai/artifact/D9gECT37hw5gBYQSiei4JC")!
}

enum DocketStore {
    /// ~/.claude/docket/docket.json in the real home folder. Not an App Group container:
    /// macOS blocks the launchd writer from those. The sandboxed widget reads this folder through
    /// a read-only `home-relative-path` exception, and its own home is a container, so ask getpwuid.
    static var fileURL: URL? {
        guard let home = getpwuid(getuid())?.pointee.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: home)).appendingPathComponent(".claude/docket/docket.json")
    }

    static func load() -> DocketData? {
        guard let url = fileURL, let raw = try? Data(contentsOf: url) else { return nil }
        return decode(raw)
    }

    static func decode(_ raw: Data) -> DocketData? {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(DocketData.self, from: raw)
    }
}

extension DocketData {
    /// Gallery placeholder and the app preview before any real data exists.
    static var sample: DocketData {
        let now = Date.now
        let stamp = DocketModel.iso.string(from: now)
        let day = DocketModel.dayString(now)
        func inDays(_ n: Int) -> String {
            DocketModel.dayString(Calendar.current.date(byAdding: .day, value: n, to: now) ?? now)
        }
        return DocketData(
            updatedAt: stamp,
            mac: Mac(updatedAt: stamp, batteryPct: 86, batteryHealthPct: 90, cycles: 297, thermal: "nominal",
                     memFreePct: 49, diskFreeGb: 64, diskTotalGb: 460, issues: []),
            brief: Brief(
                updatedAt: stamp, date: day,
                oneThing: "Send the chapter 2 draft to your supervisor",
                today: [
                    Item(title: "Chapter 2 draft to supervisor", tag: "phd", due: "\(day) 17:00"),
                    Item(title: "Sprint review notes", tag: "work", due: "\(day) 11:30"),
                    Item(title: "Reply to lab about MIC assay", tag: "phd", due: day),
                ],
                week: [
                    Item(title: "MIC results write-up", tag: "phd", due: inDays(2)),
                    Item(title: "Design crit: onboarding flow", tag: "work", due: inDays(3)),
                    Item(title: "Pay electricity bill", tag: "personal", due: inDays(4)),
                ],
                overdueCount: 0, openCount: 12, weekCount: 5, waitingCount: 3, nodateCount: 4,
                nextDeadline: Item(title: "Thesis committee report", tag: "phd", due: inDays(9))),
            scan: Scan(updatedAt: stamp, scannedAt: stamp, agentsRunning: 2,
                       agents: [Agent(title: "Inbox Docket tabs", project: "docket"),
                                Agent(title: "MIC figures", project: "phd")]))
    }
}
