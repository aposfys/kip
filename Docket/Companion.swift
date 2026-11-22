import AppKit
import ServiceManagement
import SwiftUI
import UserNotifications
import WidgetKit

// MARK: - Notifications

enum Notifier {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private static func request(id: String, title: String, body: String) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body.count > 400 ? String(body.prefix(399)) + "…" : body
        content.sound = .default
        return UNNotificationRequest(identifier: id, content: content, trigger: nil)
    }

    static func post(id: String, title: String, body: String) {
        UNUserNotificationCenter.current().add(request(id: id, title: title, body: body))
    }

    /// For the headless task run, which exits right after posting.
    static func postAndWait(id: String, title: String, body: String) {
        let done = DispatchSemaphore(value: 0)
        UNUserNotificationCenter.current().add(request(id: id, title: title, body: body)) { _ in done.signal() }
        _ = done.wait(timeout: .now() + 10)
    }
}

/// Shows Docket's banners while the app itself is running, which for a menu-bar app is always.
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}

/// The proactive nudge: one notification when tasks go overdue, then quiet until the count or the day changes.
/// Mac issues only switch the robot's mood here, because pc-health.sh --alert already notifies about them
/// once per new issue, and a second banner for the same thing would be noise.
enum Alerts {
    static let defaultsKey = "lastAlertKey"

    static func key(_ model: DocketModel) -> String? {
        model.overdue > 0 ? "overdue \(model.overdue) \(model.brief?.date ?? "")" : nil
    }

    /// Returns the body to post, or nil. Never posts between 22:00 and 07:00; the morning check catches up.
    static func check(_ model: DocketModel, defaults: UserDefaults = .standard) -> String? {
        guard let key = key(model) else {
            defaults.removeObject(forKey: defaultsKey)
            return nil
        }
        let hour = Calendar.current.component(.hour, from: model.now)
        guard (7..<22).contains(hour), defaults.string(forKey: defaultsKey) != key else { return nil }
        defaults.set(key, forKey: defaultsKey)
        var body = model.overdue == 1 ? "1 task is overdue." : "\(model.overdue) tasks are overdue."
        if let issue = model.issues.first { body += " Mac: \(issue)." }
        return body
    }
}

// MARK: - Menu-bar icon

/// The robot glyph as a template image, so the menu bar tints it for light and dark.
@MainActor
enum MenuIcon {
    private static var cache: [Mood: NSImage] = [:]

    static func image(_ mood: Mood) -> NSImage {
        if let image = cache[mood] { return image }
        let renderer = ImageRenderer(content: RobotGlyph(mood: mood, color: .black).frame(height: 18))
        renderer.scale = 2
        let image: NSImage
        if let cg = renderer.cgImage {
            image = NSImage(cgImage: cg, size: NSSize(width: CGFloat(cg.width) / 2, height: CGFloat(cg.height) / 2))
        } else {
            image = NSImage(systemSymbolName: "face.smiling", accessibilityDescription: nil) ?? NSImage()
        }
        image.isTemplate = true
        image.accessibilityDescription = "Docket, \(mood.label)"
        cache[mood] = image
        return image
    }
}

struct MenuBarLabel: View {
    var store: CompanionStore

    var body: some View {
        let model = store.model
        Image(nsImage: MenuIcon.image(model.mood))
            .accessibilityLabel(model.robotLabel)
    }
}

// MARK: - Store

enum CompanionTab: String, CaseIterable, Identifiable {
    case today = "Today", ask = "Ask", tasks = "Tasks"
    var id: String { rawValue }
}

struct TaskDraft: Identifiable {
    var task: DocketTask
    var isNew: Bool
    /// The Ask text this draft came from, so the editor can offer to ask once instead.
    var askText: String?
    var id: String { task.id }
}

@Observable @MainActor
final class CompanionStore {
    static let shared = CompanionStore()

    var data: DocketData? = DocketStore.load()
    var now = Date.now
    var tasks: [DocketTask] = TaskStore.all()
    var tab = CompanionTab.today
    var problem: String?

    var actionTitle: String?
    var actionResult: RunResult?
    var actionRunning = false
    @ObservationIgnored private var actionJob: Job?

    var question = ""
    var engine = Engine.claude
    @ObservationIgnored private var engineChosen = false
    var asking = false
    var answer: RunResult?
    @ObservationIgnored private var askJob: Job?

    var draft: TaskDraft?
    var runningTasks: Set<String> = []

    private(set) var voiceOn = UserDefaults.standard.bool(forKey: "voiceOn")
    var listening = false
    var voiceNote: String?
    @ObservationIgnored private let listener = Listener()
    private(set) var openAtLogin = SMAppService.mainApp.status == .enabled

    @ObservationIgnored private var timer: Timer?

    var model: DocketModel { DocketModel(data: data, now: now) }
    var looksLikeTask: Bool { TaskParser.parse(question) != nil }

    /// Called once at launch, after the command-line modes have exited.
    func start() {
        guard timer == nil else { return }
        UNUserNotificationCenter.current().delegate = NotificationPresenter.shared
        Notifier.requestAuthorization()
        TaskStore.syncAgents()
        reload()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            MainActor.assumeIsolated { CompanionStore.shared.reload() }
        }
    }

    /// Re-reads docket.json and the task list (cheap local files), then checks for a new overdue nudge.
    func reload() {
        now = .now
        let fresh = DocketStore.load()
        if fresh != data { data = fresh }
        let list = TaskStore.all()
        if list != tasks { tasks = list }
        if let body = Alerts.check(model) {
            Notifier.post(id: "docket-alert-\(Int(now.timeIntervalSince1970))", title: "Docket", body: body)
        }
    }

    // MARK: Quick actions

    private func runAction(_ title: String, _ work: @escaping @Sendable (Job) -> RunResult, then: (() -> Void)? = nil) {
        guard !actionRunning else { return }
        let job = Job()
        actionJob = job
        actionTitle = title
        actionResult = nil
        actionRunning = true
        Task {
            let result = await Task.detached { work(job) }.value
            actionResult = result
            actionRunning = false
            actionJob = nil
            then?()
        }
    }

    func briefNow() { runAction("Brief") { Runner.briefNow(job: $0) } }

    func healthCheck() {
        runAction("Health check", { job in
            let report = Runner.healthReport(job: job)
            _ = ContentView.runHealthCheck()  // fresh numbers into docket.json, like the hourly agent
            return report
        }, then: {
            WidgetCenter.shared.reloadAllTimelines()
            CompanionStore.shared.reload()
        })
    }

    func diskPreview() { runAction("Disk preview") { Runner.diskPreview(job: $0) } }
    func openInbox() { NSWorkspace.shared.open(DocketLinks.inbox) }
    func stopAction() { actionJob?.cancel() }

    func clearAction() {
        actionTitle = nil
        actionResult = nil
    }

    // MARK: Ask

    /// A scheduled phrasing ("every Monday 9:00 …") opens the task editor to confirm; anything else is asked once.
    func send() {
        let q = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !asking else { return }
        if let parsed = TaskParser.parse(q) {
            let task = DocketTask(id: DocketTask.newID(), prompt: parsed.prompt,
                                  engine: engineChosen ? engine : Engine.guess(parsed.prompt), schedule: parsed.schedule)
            draft = TaskDraft(task: task, isNew: true, askText: q)
        } else {
            askOnce(q, engine: engine)
        }
    }

    func askOnce(_ q: String, engine: Engine) {
        draft = nil
        tab = .ask
        let job = Job()
        askJob = job
        asking = true
        answer = nil
        Speaker.shared.stop()
        Task {
            let result = await Task.detached { Runner.ask(q, engine: engine, job: job) }.value
            answer = result
            asking = false
            askJob = nil
            if voiceOn, result.ok { Speaker.shared.speak(result.text) }
        }
    }

    func stopAsking() { askJob?.cancel() }

    /// Picks the engine from the words until the user picks one by hand.
    func questionChanged() {
        if question.isEmpty { engineChosen = false }
        if !engineChosen { engine = Engine.guess(question) }
    }

    func chooseEngine(_ e: Engine) {
        engine = e
        engineChosen = true
    }

    // MARK: Tasks

    func newTask() {
        draft = TaskDraft(task: DocketTask(id: DocketTask.newID(), prompt: "", engine: .claude,
                                           schedule: Schedule(kind: .weekly, weekdays: [1])),
                          isNew: true, askText: nil)
    }

    func edit(_ task: DocketTask) { draft = TaskDraft(task: task, isNew: false, askText: nil) }
    func cancelDraft() { draft = nil }

    func save(_ task: DocketTask) {
        var task = task
        task.prompt = task.prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard persist(task) else { return }
        if draft?.askText != nil { question = "" }
        draft = nil
        tab = .tasks
    }

    func togglePause(_ task: DocketTask) {
        var task = task
        task.paused.toggle()
        persist(task)
    }

    /// Writes the task and its LaunchAgent. Keeps run results that landed while the editor was open.
    @discardableResult
    private func persist(_ task: DocketTask) -> Bool {
        var task = task
        if let current = TaskStore.load(task.id) {
            task.lastRun = current.lastRun
            task.lastOK = current.lastOK
            task.lastResult = current.lastResult
        }
        defer { tasks = TaskStore.all() }
        do {
            try TaskStore.save(task)
            problem = nil
            return true
        } catch {
            problem = error.localizedDescription
            return false
        }
    }

    /// The row asks first; this is the confirmed delete.
    func delete(_ task: DocketTask) {
        TaskStore.delete(task.id)
        tasks = TaskStore.all()
    }

    func runNow(_ task: DocketTask) {
        let id = task.id
        guard !runningTasks.contains(id) else { return }
        runningTasks.insert(id)
        Task {
            _ = await Task.detached { TaskStore.runHeadless(id) }.value
            runningTasks.remove(id)
            tasks = TaskStore.all()
        }
    }

    func openLogs() {
        try? FileManager.default.createDirectory(at: TaskStore.dir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(TaskStore.dir)
    }

    // MARK: Settings

    func setVoice(_ on: Bool) {
        voiceOn = on
        UserDefaults.standard.set(on, forKey: "voiceOn")
        if !on {
            listener.stop()
            Speaker.shared.stop()
            voiceNote = nil
        }
    }

    func toggleListening() {
        if listening { return listener.stop() }
        voiceNote = nil
        listening = true
        listener.start(onText: { text in
            MainActor.assumeIsolated {
                CompanionStore.shared.question = text
                CompanionStore.shared.questionChanged()
            }
        }, onEnd: { note in
            MainActor.assumeIsolated {
                CompanionStore.shared.listening = false
                CompanionStore.shared.voiceNote = note
            }
        })
    }

    func setOpenAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            problem = "Open at login: \(error.localizedDescription)"
        }
        openAtLogin = SMAppService.mainApp.status == .enabled
    }
}

// MARK: - Popover

struct CompanionView: View {
    @Environment(CompanionStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let model = store.model
        VStack(alignment: .leading, spacing: 12) {
            header(model)
            if let draft = store.draft {
                TaskEditor(draft: draft).id(draft.id)
            } else {
                Picker("Section", selection: Bindable(store).tab) {
                    ForEach(CompanionTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                switch store.tab {
                case .today: TodayPane(model: model)
                case .ask: AskPane()
                case .tasks: TasksPane()
                }
            }
            if let problem = store.problem {
                HStack(alignment: .top) {
                    Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    Spacer()
                    Button("Dismiss") { store.problem = nil }.buttonStyle(.borderless)
                }
                .font(.callout)
            }
        }
        .padding(14)
        .frame(width: 380)
        .environment(\.robotAnimates, true)
    }

    private func header(_ model: DocketModel) -> some View {
        HStack(spacing: 10) {
            RobotView(mood: model.mood, stale: model.isBriefStale).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 1) {
                Text("Docket").font(.headline)
                Text(model.moodLine).font(.callout).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Menu {
                Toggle("Voice (on-device)", isOn: Binding(get: { store.voiceOn }, set: { store.setVoice($0) }))
                Toggle("Open at login", isOn: Binding(get: { store.openAtLogin }, set: { store.setOpenAtLogin($0) }))
                Divider()
                Button("Widget preview…") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                Button("Open Inbox Docket") { store.openInbox() }
                Divider()
                Button("Quit Docket") { NSApp.terminate(nil) }
            } label: {
                Label("Settings", systemImage: "gearshape").labelStyle(.iconOnly)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Voice, open at login, widget preview and quit")
        }
    }
}

/// A light card behind each block of the popover.
private struct Panel<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let title { Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary) }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

struct TodayPane: View {
    @Environment(CompanionStore.self) private var store
    var model: DocketModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Panel(title: "Mac") {
                Text(macLine).font(.callout)
                ForEach(model.issues, id: \.self) {
                    Label($0, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.orange)
                }
            }
            Panel(title: model.brief == nil ? "Today" : "Today, brief \(model.ageText)") {
                if model.brief == nil {
                    Text("No brief yet. It arrives with the morning task.").font(.callout).foregroundStyle(.secondary)
                } else {
                    Text(model.oneThing).font(.callout.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    if model.overdue > 0 {
                        Label(model.overdue == 1 ? "1 overdue" : "\(model.overdue) overdue",
                              systemImage: "clock.badge.exclamationmark").font(.callout).foregroundStyle(.red)
                    }
                    ForEach(Array(model.today.prefix(5).enumerated()), id: \.offset) { _, item in
                        HStack(spacing: 8) {
                            Text(item.title).lineLimit(1)
                            Spacer(minLength: 4)
                            if let due = DueFormat.format(item.due, now: model.now)?.short {
                                Text(due).monospacedDigit().foregroundStyle(due.hasSuffix("late") ? .red : .secondary)
                            }
                        }
                        .font(.callout)
                    }
                    if model.today.count > 5 {
                        Text("and \(model.today.count - 5) more").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    action("Run brief now", "sparkles", help: "A short brief from docket.json, one Claude sonnet run") {
                        store.briefNow()
                    }
                    action("Health check", "stethoscope", help: "Runs pc-health.sh and refreshes the widget") {
                        store.healthCheck()
                    }
                }
                GridRow {
                    action("Disk preview", "internaldrive", help: "mo clean --dry-run: shows what could go, deletes nothing") {
                        store.diskPreview()
                    }
                    action("Open Inbox Docket", "tray.full", help: "Opens the Inbox Docket page in your browser", busy: false) {
                        store.openInbox()
                    }
                }
            }
            if store.actionTitle != nil { OutputPanel() }
        }
    }

    private var macLine: String {
        guard let mac = model.mac else { return "No Mac check yet. Press Health check." }
        var parts: [String] = []
        if let b = mac.batteryPct { parts.append("Battery \(b)%") }
        if let d = mac.diskFreeGb { parts.append("\(Int(d)) GB free") }
        if let m = mac.memFreePct { parts.append("Memory \(m)% free") }
        if let t = mac.thermal, t != "nominal" { parts.append("Thermal \(t)") }
        if let at = model.macUpdated {
            parts.append("checked " + min(at, model.now).formatted(.relative(presentation: .named)))
        }
        return parts.joined(separator: " · ")
    }

    private func action(_ title: String, _ icon: String, help: String, busy: Bool = true,
                        run: @escaping () -> Void) -> some View {
        Button(action: run) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(busy && store.actionRunning)
        .help(help)
    }
}

struct OutputPanel: View {
    @Environment(CompanionStore.self) private var store

    var body: some View {
        let result = store.actionResult
        Panel(title: nil) {
            HStack(spacing: 10) {
                Text(store.actionTitle ?? "").font(.subheadline.weight(.semibold))
                if store.actionRunning { ProgressView().controlSize(.small) }
                Spacer()
                if store.actionRunning {
                    Button("Stop") { store.stopAction() }
                } else {
                    if let text = result?.text { Button("Copy") { copy(text) } }
                    Button("Close") { store.clearAction() }
                }
            }
            .buttonStyle(.borderless)
            ScrollView {
                Text(result?.text ?? "Working. This can take a minute.")
                    .font(store.actionTitle == "Brief" ? .callout : .system(.caption, design: .monospaced))
                    .foregroundStyle(result?.ok == false ? Color.red : Color.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 170)
        }
    }
}

struct AskPane: View {
    @Environment(CompanionStore.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var store = store
        let empty = store.question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        VStack(alignment: .leading, spacing: 8) {
            TextField("Ask Docket, or set a task: “every Monday 9:00 check X and tell me”",
                      text: $store.question, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { store.send() }
                .onChange(of: store.question) { store.questionChanged() }
            HStack(spacing: 8) {
                Picker("Engine", selection: Binding(get: { store.engine }, set: { store.chooseEngine($0) })) {
                    ForEach(Engine.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .help("Claude for questions about your day. agy for web and bulk work, on Google's quota.")
                Spacer()
                if store.voiceOn {
                    Button { store.toggleListening() } label: {
                        Label(store.listening ? "Stop listening" : "Speak",
                              systemImage: store.listening ? "mic.fill" : "mic")
                    }
                    .help("On-device speech recognition. Audio never leaves the Mac.")
                }
                if store.asking {
                    Button("Stop") { store.stopAsking() }
                } else {
                    Button(store.looksLikeTask ? "Set up task" : "Send") { store.send() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.return, modifiers: .command)
                        .disabled(empty)
                }
            }
            if let note = store.voiceNote { Text(note).font(.caption).foregroundStyle(.secondary) }
            if store.looksLikeTask && !store.asking {
                Label("Looks like a task. You will see the schedule before anything is saved.",
                      systemImage: "calendar.badge.clock")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if store.asking {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Asking \(store.engine.label)…").font(.callout).foregroundStyle(.secondary)
                }
            }
            if let answer = store.answer {
                Panel(title: nil) {
                    ScrollView {
                        Text(answer.text)
                            .font(.callout)
                            .foregroundStyle(answer.ok ? Color.primary : Color.red)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 220)
                    HStack(spacing: 12) {
                        Spacer()
                        if store.voiceOn { Button("Speak") { Speaker.shared.speak(answer.text) } }
                        Button("Copy") { copy(answer.text) }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            Text("Read-only: Docket can read files but never changes, sends or deletes anything. "
                 + "Each question is one short run.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onAppear { focused = true }
    }
}

struct TasksPane: View {
    @Environment(CompanionStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button { store.newTask() } label: { Label("New task", systemImage: "plus") }
                Spacer()
                Button { store.openLogs() } label: { Label("Logs", systemImage: "doc.text") }
                    .buttonStyle(.borderless)
                    .help("Opens the folder with each task's log")
            }
            if store.tasks.isEmpty {
                Panel(title: nil) {
                    Text("No tasks yet. Type one in Ask, like “every weekday at 8:30 tell me what is overdue”, or press New task.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                ScrollView {
                    VStack(spacing: 8) { ForEach(store.tasks) { TaskRow(task: $0) } }
                }
                .frame(maxHeight: 380)
            }
            Text("Tasks run on schedule even when Docket is closed: one read-only run each time, then a notification.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct TaskRow: View {
    @Environment(CompanionStore.self) private var store
    var task: DocketTask
    @State private var confirmDelete = false

    var body: some View {
        let running = store.runningTasks.contains(task.id)
        Panel(title: nil) {
            Text(task.title).font(.callout.weight(.semibold)).lineLimit(2)
            Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let result = task.lastResult {
                Text(result).font(.caption).lineLimit(2)
                    .foregroundStyle(task.lastOK == false ? Color.red : Color.secondary)
            }
            if confirmDelete {
                HStack(spacing: 12) {
                    Text("Delete this task and its log?").font(.caption.weight(.semibold))
                    Spacer()
                    Button("Cancel") { confirmDelete = false }
                    Button("Delete", role: .destructive) { store.delete(task) }.foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            } else {
                HStack(spacing: 14) {
                    Button(running ? "Running…" : "Run now") { store.runNow(task) }.disabled(running)
                    Button(task.paused ? "Resume" : "Pause") { store.togglePause(task) }
                    Button("Edit") { store.edit(task) }
                    Spacer()
                    Button("Delete") { confirmDelete = true }.foregroundStyle(.red)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
    }

    private var detail: String {
        var parts = [task.schedule.summary, task.engine.label]
        if task.paused {
            parts.append("paused")
        } else if let next = task.schedule.next(after: store.now) {
            parts.append("next " + next.formatted(.relative(presentation: .named)))
        }
        if let last = task.lastRun {
            parts.append("ran " + last.formatted(.relative(presentation: .named)) + (task.lastOK == false ? ", failed" : ""))
        }
        return parts.joined(separator: " · ")
    }
}

/// The confirm step for a task: every field the parser guessed, editable, before anything is saved.
struct TaskEditor: View {
    @Environment(CompanionStore.self) private var store
    let draft: TaskDraft
    @State private var task: DocketTask

    init(draft: TaskDraft) {
        self.draft = draft
        _task = State(initialValue: draft.task)
    }

    var body: some View {
        let schedule = task.schedule
        let canSave = !task.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && schedule.isValid
        VStack(alignment: .leading, spacing: 10) {
            Text(draft.isNew ? (draft.askText == nil ? "New task" : "Save this as a task?") : "Edit task")
                .font(.headline)
            TextField("What should Docket check and tell you?", text: $task.prompt, axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
            Picker("Repeat", selection: $task.schedule.kind) {
                ForEach(Schedule.Kind.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .onChange(of: task.schedule.kind) {
                if task.schedule.kind == .weekly && task.schedule.weekdays.isEmpty { task.schedule.weekdays = [1] }
            }
            if schedule.kind == .weekly {
                HStack(spacing: 4) {
                    ForEach(1...7, id: \.self) { day in
                        Toggle(Schedule.dayNames[day - 1], isOn: weekday(day)).toggleStyle(.button)
                    }
                }
            }
            if schedule.kind == .monthly {
                Stepper("Day \(schedule.monthDay) of the month", value: $task.schedule.monthDay, in: 1...28)
            }
            if schedule.kind == .hourly {
                Stepper(String(format: "At :%02d past each hour", schedule.minute),
                        value: $task.schedule.minute, in: 0...55, step: 5)
            } else {
                DatePicker("Time", selection: time, displayedComponents: .hourAndMinute).datePickerStyle(.field)
            }
            Picker("Engine", selection: $task.engine) {
                ForEach(Engine.allCases) { Text($0.label).tag($0) }
            }
            .help("Claude for questions about your day. agy for web and bulk work, on Google's quota.")
            Panel(title: nil) {
                if schedule.isValid {
                    Label(schedule.summary + (schedule.next(after: .now).map {
                        ". Next run " + $0.formatted(date: .abbreviated, time: .shortened)
                    } ?? ""), systemImage: "calendar")
                } else {
                    Label("Pick at least one day.", systemImage: "calendar.badge.exclamationmark").foregroundStyle(.red)
                }
                Text("Each run is read-only and posts its answer as a notification. It never sends, changes or deletes anything.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            HStack {
                if draft.askText != nil {
                    Button("Ask once instead") { store.askOnce(task.prompt, engine: task.engine) }
                        .disabled(task.prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Spacer()
                Button("Cancel") { store.cancelDraft() }.keyboardShortcut(.cancelAction)
                Button(draft.isNew ? "Save task" : "Save") { store.save(task) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
    }

    private func weekday(_ day: Int) -> Binding<Bool> {
        Binding(get: { task.schedule.weekdays.contains(day) }, set: { on in
            var days = Set(task.schedule.weekdays)
            if on { days.insert(day) } else { days.remove(day) }
            task.schedule.weekdays = days.sorted()
        })
    }

    private var time: Binding<Date> {
        Binding(get: {
            Calendar.current.date(bySettingHour: task.schedule.hour, minute: task.schedule.minute, second: 0, of: .now) ?? .now
        }, set: { date in
            let c = Calendar.current.dateComponents([.hour, .minute], from: date)
            task.schedule.hour = c.hour ?? 9
            task.schedule.minute = c.minute ?? 0
        })
    }
}

@MainActor
private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}
