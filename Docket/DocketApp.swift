import AppKit
import SwiftUI
import WidgetKit

@main
struct DocketApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Docket", id: "main") { ContentView() }
            .windowResizability(.contentSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let args = CommandLine.arguments
        if args.contains("--selftest") {
            SelfTest.run()
            exit(0)
        }
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            Snapshot.write(to: URL(fileURLWithPath: args[i + 1]))
            exit(0)
        }
    }

    /// shortcut: if macOS hands the widget's tap URL to this app instead of the browser,
    /// pass it on. Drop this once taps are confirmed to open the browser directly.
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "https" { NSWorkspace.shared.open(url) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct ContentView: View {
    @State private var data = DocketStore.load()
    @State private var mood: Mood?
    @State private var status = ""
    @State private var working = false

    var body: some View {
        let model = DocketModel(data: data ?? .sample, moodOverride: mood)
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Docket").font(.largeTitle.bold())
                    Text(sourceLine(model)).font(.callout).foregroundStyle(.secondary)
                }
                Spacer(minLength: 24)
                Picker("Mood", selection: $mood) {
                    Text("Auto").tag(Mood?.none)
                    ForEach(Mood.allCases) { Text($0.label).tag(Mood?.some($0)) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 340)
            }

            HStack(alignment: .top, spacing: 20) {
                VStack(alignment: .leading, spacing: 20) {
                    WidgetPreview(model: model, family: .small)
                    WidgetPreview(model: model, family: .medium)
                }
                WidgetPreview(model: model, family: .large)
            }

            HStack(spacing: 10) {
                Button(action: refresh) { Label("Refresh", systemImage: "arrow.clockwise") }
                    .buttonStyle(.glassProminent)
                    .disabled(working)
                Button { NSWorkspace.shared.open(DocketLinks.inbox) } label: {
                    Label("Open Inbox Docket", systemImage: "tray.full")
                }
                .buttonStyle(.glass)
                Text(status).font(.callout).foregroundStyle(.secondary)
            }

            Text("Add it to your desktop: right-click the desktop, choose Edit Widgets, then search for Docket.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(24)
        .fixedSize()
    }

    private func sourceLine(_ model: DocketModel) -> String {
        guard data != nil else { return "No data yet, showing a sample." }
        let mac = DocketModel(data: data).macUpdated.map {
            RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: .now)
        } ?? "never"
        return "Live data. \(model.ageSpoken). Mac checked \(mac)."
    }

    private func refresh() {
        working = true
        status = "Checking your Mac…"
        Task {
            let ok = await Task.detached { Self.runHealthCheck() }.value
            data = DocketStore.load()
            WidgetCenter.shared.reloadAllTimelines()
            status = ok ? "Updated" : "Health check failed. See ~/.claude/scripts/pc-health.log"
            working = false
        }
    }

    /// Same pipeline as the hourly LaunchAgent: pc-health.sh --json into the writer's `mac` part.
    nonisolated static func runHealthCheck() -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", #""$HOME/.claude/scripts/pc-health.sh" --json | /usr/bin/python3 "$HOME/.claude/scripts/docket-widget-write.py" mac"#]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            return p.terminationStatus == 0
        } catch {
            return false
        }
    }
}

/// A widget-sized card the way the desktop draws it: system padding, rounded continuous corners.
struct WidgetPreview: View {
    var model: DocketModel
    var family: DocketFamily

    var body: some View {
        DocketCard(model: model, family: family)
            .padding(16)
            .frame(width: family.size.width, height: family.size.height)
            .background(DocketBackground())
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 4)
    }
}
