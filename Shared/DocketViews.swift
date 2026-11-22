import SwiftUI
import WidgetKit

/// kip's colours on paper. Coral is kept for alerts and overdue items; calm kip's blues carry text accents.
enum Palette {
    static let calm = Robot.Ink.palette(.calm)
    static let blue = Color(hex: calm.body)
    static let navy = Color(hex: calm.line)
    static let coral = Color(hex: Robot.Ink.coral)
    /// The card: warm off-white paper, or a warm dark paper.
    static func paper(_ scheme: ColorScheme) -> Color { Color(hex: scheme == .dark ? 0x26231F : Robot.Ink.paper) }

    /// Small accent text and rings: navy on paper is 7.5:1, pale blue on the dark paper 11:1.
    static func accent(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: calm.back) : navy }
    /// A mood's own accent: its line colour on paper (5.6:1 or more), its pale back colour on dark paper.
    static func mood(_ mood: Mood, stale: Bool, _ scheme: ColorScheme) -> Color {
        let p = Robot.Ink.palette(mood, stale: stale)
        return Color(hex: scheme == .dark ? p.back : p.line)
    }
    /// Alert text: 5.9:1 or more on paper, 5.4:1 or more on the dark paper and its tinted pills.
    static func alert(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color(hex: 0xFF7B63) : Color(hex: 0xB8321A) }
    /// The large widget's header band: a slightly deeper sheet of the same paper.
    static func band(_ scheme: ColorScheme) -> Color { scheme == .dark ? Color.white.opacity(0.05) : Color(hex: 0xEFE6D4).opacity(0.7) }
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

/// A warm paper card, light or dark, with a faint grain.
struct DocketBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Palette.paper(scheme).overlay {
            PaperGrain().opacity(scheme == .dark ? 0.6 : 1).accessibilityHidden(true)
        }
    }
}

/// Paper grain: fixed specks and short fibres, the same on every redraw.
struct PaperGrain: View {
    var body: some View {
        Canvas { ctx, size in
            var seed: UInt64 = 0x9E3779B97F4A7C15
            func next() -> CGFloat {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return CGFloat(seed >> 33) / CGFloat(1 << 31)
            }
            let count = Int(size.width * size.height / 90)
            for i in 0..<count {
                let p = CGPoint(x: next() * size.width, y: next() * size.height)
                let shade = next() < 0.5 ? Color(hex: 0x8A7A5C) : Color.white
                if i % 9 == 0 {   // a fibre
                    var fibre = Path()
                    fibre.move(to: p)
                    fibre.addLine(to: CGPoint(x: p.x + 2 + next() * 4, y: p.y + (next() - 0.5) * 2))
                    ctx.stroke(fibre, with: .color(shade.opacity(0.07)), lineWidth: 0.5)
                } else {
                    let r = 0.3 + next() * 0.5
                    ctx.fill(Path(ellipseIn: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r)),
                             with: .color(shade.opacity(0.06 + next() * 0.06)))
                }
            }
        }
    }
}

struct DocketCard: View {
    var model: DocketModel
    var family: DocketFamily
    @Environment(\.colorScheme) private var scheme

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
            VStack(alignment: .leading, spacing: 2) {
                robot.frame(width: 92, height: 92)
                Spacer(minLength: 0)
                OneThingLabel().accessibilityHidden(true)
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
                    .foregroundStyle(Palette.mood(model.mood, stale: model.isBriefStale, scheme))
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
        // Rows left for the two lists: 8, less one for a Mac issue and one for the next deadline.
        // "+N more" costs a row. Today gets at most 4 rows, or 3 when space is short.
        let rows = 8 - (model.issues.isEmpty ? 0 : 1) - (model.nextDeadline == nil ? 0 : 1)
        let todayCap = rows >= 7 ? 4 : 3
        let todayLimit = Self.limit(model.today.count, rows: todayCap, cap: todayCap)
        let todayRows = max(1, todayLimit + (model.today.count > todayLimit ? 1 : 0))
        let weekLimit = min(Self.limit(model.weekCount, rows: rows - todayRows, cap: 5), model.week.count)
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
                    // The mood line wins: the agents count shrinks to a number, then goes, before the pill truncates.
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 8) {
                            StatusPill(model: model).fixedSize()
                            if model.agentsRunning > 0 { AgentsLabel(model: model).fixedSize() }
                        }
                        HStack(spacing: 6) {
                            StatusPill(model: model).fixedSize()
                            if model.agentsRunning > 0 { AgentsLabel(model: model, compact: true).fixedSize() }
                        }
                        StatusPill(model: model)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(8)
            .layoutPriority(1)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Palette.band(scheme)))

            if let deadline = model.nextDeadline { DeadlineRow(item: deadline, model: model) }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "Today", count: model.today.count, note: model.mailChecked)
                ItemList(items: model.today, limit: todayLimit, empty: "Nothing due today", model: model)
            }
            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: "This week", count: model.weekCount, note: model.laterLine)
                ItemList(items: model.week, limit: weekLimit, empty: "Clear week ahead", model: model,
                         total: model.weekCount)
            }
            if let issue = model.issues.first { IssueRow(text: issue) }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                BatteryRing(model: model)
                DiskRing(model: model)
                Spacer(minLength: 4)
                // The chip never truncates; "N open" drops when the two do not fit.
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 14) {
                        Text("\(model.open) open").font(.caption2).foregroundStyle(Color.muted)
                        OverdueChip(count: model.overdue)
                    }
                    OverdueChip(count: model.overdue)
                }
                .fixedSize(horizontal: false, vertical: true)
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
        Text("ONE THING").font(.caption2.weight(.bold)).kerning(0.6).foregroundStyle(Color.muted)
    }
}

/// The mood line in a capsule, in kip's mood colour: alert-tinted when worried.
struct StatusPill: View {
    var model: DocketModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let alert = model.mood == .worried && !model.isBriefStale
        let color = alert ? Palette.alert(scheme) : Palette.mood(model.mood, stale: model.isBriefStale, scheme)
        let tint = Color(hex: Robot.Ink.palette(model.mood, stale: model.isBriefStale).body)
        HStack(spacing: 4) {
            Image(systemName: Self.symbol(model.mood))
            Text(model.moodLine).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(alert ? Palette.coral.opacity(scheme == .dark ? 0.14 : 0.12) : tint.opacity(scheme == .dark ? 0.16 : 0.22)))
        .accessibilityElement(children: .combine)
    }

    static func symbol(_ mood: Mood) -> String {
        switch mood {
        case .resting: "moon.fill"
        case .calm: "sun.max.fill"
        case .happy: "checkmark.seal.fill"
        case .busy: "bolt.fill"
        case .worried: "exclamationmark.triangle.fill"
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
    /// Quiet text on the right, such as "3 waiting · 4 no date".
    var note: String? = nil

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
                Text(title.uppercased())
                if count > 0 { Text("\(count)").monospacedDigit() }
            }
            .font(.caption2.weight(.bold))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            if let note {
                Spacer(minLength: 4)
                Text(note).font(.caption2.monospacedDigit()).lineLimit(1)
            }
        }
        .foregroundStyle(Color.muted)
    }
}

/// The next PhD or personal deadline, under the large widget's header.
struct DeadlineRow: View {
    var item: DocketData.Item
    var model: DocketModel
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let due = DueFormat.format(item.due, now: model.now)
        let late = due?.short.hasSuffix("late") == true && !model.isBriefStale
        let accent = model.isBriefStale ? Color.muted : Palette.accent(scheme)
        HStack(spacing: 6) {
            Image(systemName: "flag.fill").font(.system(size: 9, weight: .semibold)).frame(width: 12)
            Text("DEADLINE").font(.caption2.weight(.bold))
            Text(item.title).font(.footnote.weight(.semibold)).foregroundStyle(Color.primary).lineLimit(1)
            Spacer(minLength: 4)
            if let due {
                Text(due.short)
                    .font(.caption2.weight(.semibold).monospacedDigit())
                    .foregroundStyle(late ? Palette.alert(scheme) : Color.muted)
                    .lineLimit(1)
            }
        }
        .foregroundStyle(accent)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(["Next deadline", item.title, due?.spoken].compactMap { $0 }.joined(separator: ", "))
    }
}

/// "2 agents" beside the large widget's status pill, from the last inbox scan.
struct AgentsLabel: View {
    var model: DocketModel
    var compact = false

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
            Text(compact ? "\(model.agentsRunning)" : model.agentsRunning == 1 ? "1 agent" : "\(model.agentsRunning) agents")
                .monospacedDigit()
        }
        .font(.caption2)
        .foregroundStyle(Color.muted)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.agentsSpoken)
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
    /// The full count when `items` is cut short (the brief sends at most 10 for the week).
    var total: Int? = nil

    var body: some View {
        let hidden = max(total ?? 0, items.count) - min(limit, items.count)
        VStack(alignment: .leading, spacing: 3) {
            if items.isEmpty {
                Text(empty).font(font).foregroundStyle(Color.muted)
            }
            ForEach(Array(items.prefix(limit).enumerated()), id: \.offset) { _, item in
                ItemRow(item: item, now: model.now, stale: model.isBriefStale, font: font)
            }
            if showMore && hidden > 0 && !items.isEmpty {
                Text("+\(hidden) more").font(.caption2).foregroundStyle(Color.muted)
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
    @Environment(\.colorScheme) private var scheme

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
        return warn ? Palette.coral : Palette.accent(scheme)
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
