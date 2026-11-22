import AppKit
import SwiftUI

/// `Docket --snapshot <dir>` writes docket-light.png and docket-dark.png:
/// every mood plus the stale state, in all three sizes, from the real data file.
@MainActor
enum Snapshot {
    static func write(to dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let live = DocketStore.load()
        var data = live ?? .sample
        if data.brief == nil { data.brief = DocketData.sample.brief }  // before the first morning brief
        let source = live == nil ? "sample data" : live?.brief == nil ? "live Mac data, sample brief" : "live data"
        for scheme in [ColorScheme.light, .dark] {
            let sheet = SnapshotSheet(data: data, source: source, scheme: scheme)
                .environment(\.colorScheme, scheme)
            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 2
            guard let image = renderer.cgImage,
                  let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { continue }
            let url = dir.appendingPathComponent("docket-\(scheme == .dark ? "dark" : "light").png")
            do {
                try png.write(to: url)
                print(url.path)
            } catch {
                FileHandle.standardError.write(Data("snapshot: \(error.localizedDescription)\n".utf8))
            }
        }
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
            + [("Stale (seen 48h later)", DocketModel(data: data, now: now.addingTimeInterval(48 * 3600)))]
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
        print("selftest ok")
    }
}
