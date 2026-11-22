import Foundation

/// Which one-shot answers a question or runs a task. Claude for short questions about the docket,
/// agy for web and bulk work, so those spend Google quota instead of Claude tokens.
enum Engine: String, Codable, CaseIterable, Identifiable {
    case claude, agy
    var id: String { rawValue }
    var label: String { self == .claude ? "Claude sonnet" : "agy (Gemini)" }

    static func guess(_ prompt: String) -> Engine {
        let p = prompt.lowercased()
        let bulk = ["web", "online", "internet", "google", "research", "search", "news", "latest", "look up",
                    "papers", "articles", "every file", "all files", "codebase", "whole repo"]
        return bulk.contains { p.contains($0) } ? .agy : .claude
    }
}

struct RunResult: Equatable {
    var ok: Bool
    var text: String
}

/// One child process with a time limit. Output goes to temp files, so a long answer never fills a pipe.
final class Job: @unchecked Sendable {
    private let process = Process()

    func cancel() { if process.isRunning { process.terminate() } }

    /// Blocks until the process ends. Call it off the main thread.
    func run(_ exe: String, _ args: [String], stdin: String? = nil, cwd: URL? = nil, timeout: TimeInterval) -> RunResult {
        let fm = FileManager.default
        let tmp = fm.temporaryDirectory.appendingPathComponent("docket-\(UUID().uuidString)")
        try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tmp) }
        let out = tmp.appendingPathComponent("out"), err = tmp.appendingPathComponent("err"), inp = tmp.appendingPathComponent("in")
        fm.createFile(atPath: out.path, contents: nil)
        fm.createFile(atPath: err.path, contents: nil)
        fm.createFile(atPath: inp.path, contents: Data((stdin ?? "").utf8))

        process.executableURL = URL(fileURLWithPath: exe)
        process.arguments = args
        process.currentDirectoryURL = cwd
        var env = ProcessInfo.processInfo.environment
        env["PATH"] = Runner.loginPath
        env["NO_COLOR"] = "1"
        env["TERM"] = "dumb"
        process.environment = env
        do {
            process.standardInput = try FileHandle(forReadingFrom: inp)
            process.standardOutput = try FileHandle(forWritingTo: out)
            process.standardError = try FileHandle(forWritingTo: err)
            try process.run()
        } catch {
            return RunResult(ok: false, text: "Could not start \(URL(fileURLWithPath: exe).lastPathComponent): \(error.localizedDescription)")
        }
        let timer = DispatchWorkItem { [process] in if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
        process.waitUntilExit()
        timer.cancel()

        let stdout = Runner.clean((try? String(contentsOf: out, encoding: .utf8)) ?? "")
        let stderr = Runner.clean((try? String(contentsOf: err, encoding: .utf8)) ?? "")
        if process.terminationReason == .uncaughtSignal {
            return RunResult(ok: false, text: stdout.isEmpty ? "Stopped." : stdout + "\n\nStopped.")
        }
        let ok = process.terminationStatus == 0
        let text = ok || stderr.isEmpty ? stdout : [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
        return RunResult(ok: ok, text: text.isEmpty ? (ok ? "Done, no output." : "Failed with code \(process.terminationStatus).") : text)
    }
}

/// The local CLIs behind the companion. None of this talks to the network itself; claude and agy do,
/// and only when the user asks a question or a task they created comes due.
enum Runner {
    static let home = FileManager.default.homeDirectoryForCurrentUser  // the app is not sandboxed
    static let docketDir = home.appendingPathComponent(".claude/docket")
    static let agyRun = home.appendingPathComponent(".claude/skills/agy-delegate/agy-run.sh").path
    static let pcHealth = home.appendingPathComponent(".claude/scripts/pc-health.sh").path

    /// The login shell's PATH, so Homebrew and nvm CLIs resolve when Finder or launchd starts the app.
    static let loginPath: String = {
        let fallback = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        let p = Process()
        let pipe = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "print -r -- $PATH"]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return fallback }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        let path = String(decoding: data, as: UTF8.self).split(separator: "\n").last.map(String.init) ?? ""
        return path.contains("/") ? path : fallback
    }()

    static func which(_ tool: String) -> String? {
        loginPath.split(separator: ":").map { "\($0)/\(tool)" }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Drops terminal colour codes and trims.
    static func clean(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{1B}\\[[0-9;?]*[A-Za-z]", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static let systemPrompt = """
        You are kip, a small companion in the user's Mac menu bar. Answer in plain text, at most 120 words, \
        no headings. You can read files but never change, send or delete anything. The user's docket.json \
        (Mac health, today's brief, last inbox scan) is in the message. If a question needs the web or reading \
        many files, say it is better sent to agy.
        """

    /// Read-only headless Claude: --safe-mode skips CLAUDE.md, skills, plugins, hooks and MCP;
    /// --tools leaves only Read, Grep and Glob. The prompt goes in on stdin.
    static func claudeArgs() -> [String] {
        ["-p", "--model", "sonnet", "--max-turns", "6", "--safe-mode", "--strict-mcp-config",
         "--tools", "Read,Grep,Glob", "--allowedTools", "Read,Grep,Glob",
         "--no-session-persistence", "--output-format", "text", "--system-prompt", systemPrompt]
    }

    static func message(_ question: String) -> String {
        let docket = DocketStore.fileURL.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "{}"
        return "\(question)\n\n<docket.json>\n\(docket)\n</docket.json>"
    }

    /// One question, one answer. Blocks; call it off the main thread.
    static func ask(_ question: String, engine: Engine, job: Job = Job()) -> RunResult {
        try? FileManager.default.createDirectory(at: docketDir, withIntermediateDirectories: true)
        switch engine {
        case .claude:
            guard let claude = which("claude") else {
                return RunResult(ok: false, text: "The claude CLI is not on your login PATH.")
            }
            var r = job.run(claude, claudeArgs(), stdin: message(question), cwd: docketDir, timeout: 300)
            let t = r.text.lowercased()
            if !r.ok, t.contains("authenticate") || t.contains("not logged in") || t.contains("/login") {
                r.text = "Not logged in. Run claude in a terminal and sign in with /login."
            }
            return r
        case .agy:
            guard FileManager.default.isExecutableFile(atPath: agyRun) else {
                return RunResult(ok: false, text: "agy-run.sh is missing from ~/.claude/skills/agy-delegate.")
            }
            // -p is agy's plan mode: it may read but not edit. A quota message comes back as the answer; never retry.
            let brief = systemPrompt.replacingOccurrences(of: " If a question needs the web or reading many files, say it is better sent to agy.", with: "")
                + "\n\n" + message(question)
            return job.run("/bin/bash", [agyRun, "-p", "-t", "600", "-d", docketDir.path, brief], cwd: docketDir, timeout: 660)
        }
    }

    /// `mo clean --dry-run`: what Mole would remove, changing nothing. Keeps the summary lines.
    static func diskPreview(job: Job = Job()) -> RunResult {
        guard let mo = which("mo") else { return RunResult(ok: false, text: "Mole (mo) is not installed.") }
        var r = job.run(mo, ["clean", "--dry-run"], cwd: home, timeout: 240)
        let lines = r.text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let keep = lines.filter { l in
            let t = l.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("➤") || t.contains(" · ") || t.hasPrefix("Potential") || t.hasPrefix("Dry run")
        }
        if r.ok, !keep.isEmpty { r.text = keep.joined(separator: "\n") }
        return r
    }

    /// pc-health.sh's own report, unchanged.
    static func healthReport(job: Job = Job()) -> RunResult {
        job.run("/bin/bash", [pcHealth], cwd: home, timeout: 120)
    }

    /// A short brief from the morning's task list and fresh Mac numbers. The full brief, with new tasks
    /// from Inbox Docket, runs only as the Claude Desktop scheduled task.
    static func briefNow(job: Job = Job()) -> RunResult {
        ask("""
            Give me my brief for right now: the one thing to do next, what is due today and overdue, \
            and any Mac issue. Say what time the task list is from.
            """, engine: .claude, job: job)
    }
}
