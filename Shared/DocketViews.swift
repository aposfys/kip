import SwiftUI
import WidgetKit

/// The robot's colours. Coral is kept for alerts and overdue items; navy and sky carry text accents.
enum Palette {
    static let blue = Color(hex: Robot.Ink.blue)
    static let navy = Color(hex: Robot.Ink.navy)
    static let coral = Color(hex: Robot.Ink.coral)

    /// Small accent text: navy on the light card is 7.9:1 or more, sky on the dark card 8.2:1 or more.
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0x6CC0FF) : navy }
    /// Alert text: 5.3:1 or more on the light card, 5.4:1 or more on the dark card and its tinted pills.
    static func alert(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xFF7B63) : Color(hex: 0xB8321A) }
    /// Tint for the large widget's header band and the status pill.
    static let band = blue.opacity(0.08)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }

    /// Secondary text that still passes AA on both backgrounds (`.secondary` is too light at caption sizes).
    static let muted = Color.primary.opacity(0.7)
}

enum DocketFamily: String, CaseIterable, Identifiable {
    case small, medium, large
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    /// Approximate macOS desktop widget sizes, for the app preview and snapshots.
    var size: CGSize {
        switch self {
        case .small: CGSize(width: 170, height: 170)
        case .medium: CGSize(width: 364, height: 170)
        case .large: CGSize(width: 364, height: 382)
        }
    }
}

/// A quiet blue-tinted card, light or dark.
struct DocketBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        LinearGradient(colors: scheme == .dark ? [Color(hex: 0x1A2129), Color(hex: 0x12171D)]
                                               : [Color(hex: 0xF5FAFF), Color(hex: 0xE9F3FD)],
                       startPoint: .top, endPoint: .bottom)
    }
}

struct DocketCard: View {
    var model: DocketModel
    var family: DocketFamily

    var body: some View {
        switch family {
        case .small: small
        case .medium: medium
        case .large: large
        }
    }

    private var robot: RobotView { RobotView(mood: model.mood, stale: model.isBriefStale, label: model.robotLabel) }

    private var small: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                robot.frame(width: 92, height: 92)
                Spacer(minLength: 0)
                Text(model.oneThing)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .accessibilityLabel("One thing: \(model.oneThing)")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            AgeBadge(model: model)
        }
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 2) {
                robot.frame(width: 108, height: 108)
                Text(model.moodLine)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.muted)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .accessibilityHidden(true)
            }
            .frame(width: 112)
            .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    HStack {
                        OneThingLabel()
                        Spacer(minLength: 4)
                        AgeBadge(model: model)
                    }
                    Text(model.oneThing).font(.footnote.weight(.semibold)).lineLimit(2)
                }
                .accessibilityElement(children: .combine)
                ItemList(items: model.today, limit: 3, empty: "Nothing due today", model: model, font: .caption,
                         showMore: false)
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    BatteryRing(model: model, compact: true)
                    DiskRing(model: model, compact: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var large: some View {
        // Rows left for the two lists: 8, or 7 when a Mac issue takes a line. "+N more" costs a row.
        let rows = model.issues.isEmpty ? 8 : 7
        let todayLimit = Self.limit(model.today.count, rows: 4, cap: 4)
        let todayRows = max(1, todayLimit + (model.today.count > todayLimit ? 1 : 0))
        let weekLimit = Self.limit(model.week.count, rows: rows - todayRows, cap: 5)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                robot.frame(width: 100, height: 100)
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack {
                            OneThingLabel()
                            Spacer(minLength: 4)
                            AgeBadge(model: model)
                        }
                        Text(model.oneThing).font(.headline).lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .accessibilityElement(children: .combine)
                    StatusPill(model: model)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .layoutPriority(1)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.band))

            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Today", count: model.today.count)
                ItemList(items: model.today, limit: todayLimit, empty: "Nothing due today", model: model)
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "This week", count: model.week.count)
                ItemList(items: model.week, limit: weekLimit, empty: "Clear week ahead", model: model)
            }
            if let issue = model.issues.first { IssueRow(text: issue) }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                BatteryRing(model: model)
                DiskRing(model: model)
                Spacer(minLength: 4)
                Text("\(model.open) open").font(.caption2).foregroundStyle(Color.muted)
                OverdueChip(count: model.overdue)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// How many of `count` items fit in `rows` lines, at most `cap`, keeping a line for "+N more".
    static func limit(_ count: Int, rows: Int, cap: Int) -> Int {
        count <= min(rows, cap) ? count : max(min(cap, rows - 1), 0)
    }
}

struct OneThingLabel: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Text("ONE THING").font(.caption2.weight(.bold)).foregroundStyle(Palette.accent(scheme))
    }
}

/// The mood line in a capsule: alert-tinted when worried, quiet blue otherwise.
struct StatusPill: View {
    var model: DocketModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let alert = model.mood == .worried && !model.isBriefStale
        let color = alert ? Palette.alert(scheme) : Palette.accent(scheme)
        HStack(spacing: 4) {
            Image(systemName: Self.symbol(model.mood))
            Text(model.moodLine).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(alert ? Palette.coral.opacity(scheme == .dark ? 0.14 : 0.12) : Palette.blue.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }

    static func symbol(_ mood: Mood) -> String {
        switch mood {
        case .happy: "checkmark"
        case .busy: "bolt.fill"
        case .worried: "exclamationmark.triangle.fill"
        case .sleepy: "moon.fill"
        }
    }
}

struct AgeBadge: View {
    var model: DocketModel

    var body: some View {
        HStack(spacing: 3) {
            if model.isBriefStale { Image(systemName: "clock.arrow.circlepath") }
            Text(model.ageText)
        }
        .font(.caption2.weight(.medium).monospacedDigit())
        .foregroundStyle(Color.muted)
        .lineLimit(1)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Capsule().fill(Color.primary.opacity(model.isBriefStale ? 0.1 : 0.06)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.ageSpoken)
    }
}

struct SectionHeader: View {
    var title: String
    var count: Int

    var body: some View {
        HStack(spacing: 5) {
            Text(title.uppercased())
            if count > 0 { Text("\(count)").monospacedDigit() }
        }
        .font(.caption2.weight(.bold))
        .foregroundStyle(Color.muted)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

struct ItemList: View {
    var items: [DocketData.Item]
    var limit: Int
    var empty: String
    var model: DocketModel
    var font: Font = .footnote
    /// The medium widget has no room for the "+N more" line.
    var showMore = true

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if items.isEmpty {
                Text(empty).font(font).foregroundStyle(Color.muted)
            }
            ForEach(Array(items.prefix(limit).enumerated()), id: \.offset) { _, item in
                ItemRow(item: item, now: model.now, stale: model.isBriefStale, font: font)
            }
            if showMore && items.count > limit {
                Text("+\(items.count - limit) more").font(.caption2).foregroundStyle(Color.muted)
            }
        }
    }
}

struct ItemRow: View {
    var item: DocketData.Item
    var now: Date
    var stale: Bool
    var font: Font = .footnote
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let due = DueFormat.format(item.due, now: now)
        let late = due?.short.hasSuffix("late") == true && !stale
        HStack(spacing: 6) {
            Image(systemName: Self.symbol(item.tag))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(stale ? Color.muted : Palette.accent(scheme))
                .frame(width: 12)
            Text(item.title).font(font).lineLimit(1)
            Spacer(minLength: 4)
            if let due {
                Text(due.short)
                    .font(.caption2.weight(late ? .semibold : .regular).monospacedDigit())
                    .foregroundStyle(late ? Palette.alert(scheme) : Color.muted)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([item.title, item.tag, due?.spoken].compactMap { $0 }.joined(separator: ", "))
    }

    static func symbol(_ tag: String?) -> String {
        switch tag?.lowercased() {
        case "phd": "graduationcap.fill"
        case "work": "briefcase.fill"
        case "personal": "house.fill"
        case "cal": "calendar"
        case "mail", "yahoo": "envelope.fill"
        default: "circle.fill"
        }
    }
}

struct IssueRow: View {
    var text: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Palette.alert(scheme))
            Text(text).lineLimit(1)
        }
        .font(.footnote)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mac issue: \(text)")
    }
}

struct OverdueChip: View {
    var count: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let late = count > 0
        HStack(spacing: 4) {
            Image(systemName: late ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(late ? Palette.alert(scheme) : Palette.accent(scheme))
            Text(late ? "\(count) overdue" : "Nothing overdue")
                .foregroundStyle(late ? Palette.alert(scheme) : Color.primary)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(late ? Palette.coral.opacity(scheme == .dark ? 0.14 : 0.12) : Color.primary.opacity(0.06)))
        .accessibilityElement(children: .combine)
    }
}

struct Ring: View {
    var progress: Double?
    var symbol: String
    var value: String
    var caption: String
    var spokenLabel: String
    var warn: Bool
    var stale: Bool
    /// One line of text beside a smaller ring (medium widget).
    var compact = false

    var body: some View {
        let size: CGFloat = compact ? 22 : 28
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.12), lineWidth: compact ? 3.5 : 4)
                Circle()
                    .trim(from: 0, to: min(max(progress ?? 0, 0), 1))
                    .stroke(arc, style: StrokeStyle(lineWidth: compact ? 3.5 : 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                Image(systemName: symbol).font(.system(size: compact ? 8 : 10, weight: .semibold)).foregroundStyle(Color.muted)
            }
            .frame(width: size, height: size)
            if compact {
                HStack(spacing: 3) {
                    Text(value).font(.caption.weight(.semibold).monospacedDigit())
                    Text(caption).font(.caption2).foregroundStyle(Color.muted)
                }
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    Text(value).font(.caption.weight(.semibold).monospacedDigit())
                    Text(caption).font(.caption2).foregroundStyle(Color.muted)
                }
            }
        }
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(stale ? "\(value), not updated recently" : value)
    }

    private var arc: Color {
        if stale { return Color.primary.opacity(0.35) }
        return warn ? Palette.coral : Palette.blue
    }
}

struct BatteryRing: View {
    var model: DocketModel
    var compact = false

    var body: some View {
        let health = model.mac?.batteryHealthPct
        Ring(progress: health.map { Double($0) / 100 }, symbol: "battery.75percent",
             value: health.map { "\($0)%" } ?? "–", caption: "health", spokenLabel: "Battery health",
             warn: (health ?? 100) < 80, stale: model.isMacStale, compact: compact)
    }
}

struct DiskRing: View {
    var model: DocketModel
    var compact = false

    var body: some View {
        let free = model.mac?.diskFreeGb
        let total = model.mac?.diskTotalGb
        let progress: Double? = if let free, let total, total > 0 { free / total } else { nil }
        Ring(progress: progress, symbol: "internaldrive.fill",
             value: free.map { "\(Int($0.rounded())) GB" } ?? "–", caption: "free", spokenLabel: "Free disk space",
             warn: (free ?? 100) < 20, stale: model.isMacStale, compact: compact)
    }
}
