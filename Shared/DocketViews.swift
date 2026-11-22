import SwiftUI
import WidgetKit

/// AORI design-system colours (tokens/colors.css).
enum Palette {
    static let terracotta = Color(hex: 0xC05A28)
    static let rust = Color(hex: 0x8A3A22)
    static let scarlet = Color(hex: 0xD8784A)
    static let aegean = Color(hex: 0x1890A8)
    static let shallow = Color(hex: 0x78C0C0)
    static let ink = Color(hex: 0x2A2622)
    static let paper = Color(hex: 0xFBF7EF)
    static let night = Color(red: 0.12, green: 0.115, blue: 0.11)
    static let cheek = Color(hex: 0xF0A080)

    /// Small accent text: rust on paper is 7.3:1, scarlet on night 5.3:1 (both pass AA).
    static func label(_ scheme: ColorScheme) -> Color { scheme == .dark ? scarlet : rust }
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

struct DocketBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            scheme == .dark ? Palette.night : Palette.paper
            LinearGradient(colors: [Palette.terracotta.opacity(scheme == .dark ? 0.16 : 0.10), .clear],
                           startPoint: .topLeading, endPoint: .center)
        }
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

    private var octopus: Octopus { Octopus(mood: model.mood, label: model.octopusLabel) }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                octopus.frame(width: 54, height: 54)
                Spacer(minLength: 4)
                AgeBadge(model: model)
            }
            Spacer(minLength: 6)
            OneThing(text: model.oneThing, font: .subheadline.weight(.semibold), lines: 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                octopus.frame(width: 46, height: 46)
                Spacer(minLength: 6)
                OneThing(text: model.oneThing, font: .footnote.weight(.semibold), lines: 4)
            }
            .frame(width: 116, alignment: .leading)
            .frame(maxHeight: .infinity, alignment: .topLeading)

            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "Today", count: model.today.count, badge: model)
                ItemList(items: model.today, limit: 3, empty: "Nothing due today", model: model)
                Spacer(minLength: 0)
                HStack(spacing: 14) {
                    BatteryRing(model: model)
                    DiskRing(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                octopus.frame(width: 60, height: 60)
                VStack(alignment: .leading, spacing: 3) {
                    OneThing(text: model.oneThing, font: .headline, lines: 2)
                    Text(model.moodLine).font(.caption).foregroundStyle(Color.muted).lineLimit(1)
                }
                Spacer(minLength: 4)
                AgeBadge(model: model)
            }
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "Today", count: model.today.count)
                ItemList(items: model.today, limit: 4, empty: "Nothing due today", model: model)
            }
            VStack(alignment: .leading, spacing: 5) {
                SectionHeader(title: "This week", count: model.week.count)
                ItemList(items: model.week, limit: model.issues.isEmpty ? 5 : 4, empty: "Clear week ahead", model: model)
            }
            if let issue = model.issues.first { IssueRow(text: issue) }
            Spacer(minLength: 0)
            HStack(spacing: 14) {
                BatteryRing(model: model)
                DiskRing(model: model)
                Spacer(minLength: 4)
                VStack(alignment: .trailing, spacing: 3) {
                    OverdueChip(count: model.overdue)
                    Text("\(model.open) open").font(.caption2).foregroundStyle(Color.muted)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct OneThing: View {
    var text: String
    var font: Font
    var lines: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("ONE THING").font(.caption2.weight(.bold)).foregroundStyle(Palette.label(scheme))
            Text(text).font(font).lineLimit(lines)
        }
        .accessibilityElement(children: .combine)
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
    /// Pass the model to show the age badge on the right (medium widget).
    var badge: DocketModel? = nil

    var body: some View {
        HStack(spacing: 5) {
            HStack(spacing: 5) {
                Text(title.uppercased())
                if count > 0 { Text("\(count)").monospacedDigit() }
            }
            .font(.caption2.weight(.bold))
            .foregroundStyle(Color.muted)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 4)
            if let badge { AgeBadge(model: badge) }
        }
    }
}

struct ItemList: View {
    var items: [DocketData.Item]
    var limit: Int
    var empty: String
    var model: DocketModel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if items.isEmpty {
                Text(empty).font(.caption).foregroundStyle(Color.muted)
            }
            ForEach(Array(items.prefix(limit).enumerated()), id: \.offset) { _, item in
                ItemRow(item: item, now: model.now, stale: model.isBriefStale)
            }
            if items.count > limit {
                Text("+\(items.count - limit) more").font(.caption2).foregroundStyle(Color.muted)
            }
        }
    }
}

struct ItemRow: View {
    var item: DocketData.Item
    var now: Date
    var stale: Bool

    var body: some View {
        let due = DueFormat.format(item.due, now: now)
        HStack(spacing: 6) {
            Image(systemName: Self.symbol(item.tag))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(stale ? AnyShapeStyle(Color.muted) : AnyShapeStyle(.tint))
                .frame(width: 12)
            Text(item.title).font(.caption).lineLimit(1)
            Spacer(minLength: 4)
            if let due {
                Text(due.short).font(.caption2.monospacedDigit()).foregroundStyle(Color.muted).lineLimit(1)
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

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(text).lineLimit(1)
        }
        .font(.caption)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Mac issue: \(text)")
    }
}

struct OverdueChip: View {
    var count: Int

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: count > 0 ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(count > 0 ? Color.red : Color.green)
            Text(count > 0 ? "\(count) overdue" : "Nothing overdue")
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(Color.primary.opacity(0.07)))
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

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(Color.primary.opacity(0.15), lineWidth: 4)
                Circle()
                    .trim(from: 0, to: min(max(progress ?? 0, 0), 1))
                    .stroke(arc, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .widgetAccentable()
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.muted)
            }
            .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 0) {
                Text(value).font(.caption.weight(.semibold).monospacedDigit())
                Text(caption).font(.caption2).foregroundStyle(Color.muted)
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityValue(stale ? "\(value), not updated recently" : value)
    }

    private var arc: AnyShapeStyle {
        if stale { return AnyShapeStyle(Color.primary.opacity(0.35)) }
        return warn ? AnyShapeStyle(Color.orange) : AnyShapeStyle(.tint)
    }
}

struct BatteryRing: View {
    var model: DocketModel

    var body: some View {
        let health = model.mac?.batteryHealthPct
        Ring(progress: health.map { Double($0) / 100 }, symbol: "battery.75percent",
             value: health.map { "\($0)%" } ?? "–", caption: "health", spokenLabel: "Battery health",
             warn: (health ?? 100) < 80, stale: model.isMacStale)
    }
}

struct DiskRing: View {
    var model: DocketModel

    var body: some View {
        let free = model.mac?.diskFreeGb
        let total = model.mac?.diskTotalGb
        let progress: Double? = if let free, let total, total > 0 { free / total } else { nil }
        Ring(progress: progress, symbol: "internaldrive.fill",
             value: free.map { "\(Int($0.rounded())) GB" } ?? "–", caption: "free", spokenLabel: "Free disk space",
             warn: (free ?? 100) < 20, stale: model.isMacStale)
    }
}
