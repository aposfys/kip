import SwiftUI
import WidgetKit

struct DocketEntry: TimelineEntry {
    let date: Date
    let data: DocketData?
}

/// Reads the local JSON only; no network. Refreshes every 20 minutes, plus an extra
/// entry at 07:00/22:00 so the robot wakes up and falls asleep on time.
struct DocketProvider: TimelineProvider {
    func placeholder(in context: Context) -> DocketEntry {
        DocketEntry(date: .now, data: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DocketEntry) -> Void) {
        completion(DocketEntry(date: .now, data: DocketStore.load() ?? .sample))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DocketEntry>) -> Void) {
        let now = Date.now
        let data = DocketStore.load()
        let refresh = now.addingTimeInterval(20 * 60)
        var entries = [DocketEntry(date: now, data: data)]
        let boundary = DocketModel.nextBoundary(after: now)
        if boundary < refresh { entries.append(DocketEntry(date: boundary, data: data)) }
        completion(Timeline(entries: entries, policy: .after(refresh)))
    }
}

struct DocketWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: DocketEntry

    var body: some View {
        DocketCard(model: DocketModel(data: entry.data, now: entry.date), family: DocketFamily(family))
            .containerBackground(for: .widget) { DocketBackground() }
            .widgetURL(DocketLinks.inbox)
    }
}

extension DocketFamily {
    init(_ family: WidgetFamily) {
        switch family {
        case .systemMedium: self = .medium
        case .systemLarge, .systemExtraLarge: self = .large
        default: self = .small
        }
    }
}

@main
struct DocketWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "DocketWidget", provider: DocketProvider()) { entry in
            DocketWidgetView(entry: entry)
        }
        .configurationDisplayName("kip")
        .description("Today's one thing, your tasks and how your Mac is doing, with kip.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
