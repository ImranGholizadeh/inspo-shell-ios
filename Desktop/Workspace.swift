// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation
import Darwin

// The workspace the desktop app opens (owner, 2026-10-13: "I want to use it
// from an x code build", the app opens tonight's editor on this Mac): the
// editor is several engines started together, which a standing start script
// does and a standing stop script ends. The app runs those two as its
// helper and writes none of their words itself: which scripts, what is said
// to them, the port that answers, the file that holds the workspace's pid
// and the engines' log all come from Config/Desktop.xcconfig. Nothing here
// draws: scripts/check-desktop.sh holds it on this Mac with stand-in scripts.

/// The desktop app's words: each is read from the app's Info.plist, where
/// Config/Desktop.xcconfig puts it, unless the environment says the same
/// word by its xcconfig name (a rehearsal on another port and state).
enum DesktopWords {
    /// InspoWorkspaceStart is INSPO_DESKTOP_WORKSPACE_START
    static func name(_ key: String) -> String {
        var parts: [String] = []
        for c in key {
            if c.isUppercase || parts.isEmpty { parts.append(String(c)) } else { parts[parts.count - 1].append(c) }
        }
        let upper = parts.map { $0.uppercased() }
        return ([upper.first ?? "", "DESKTOP"] + upper.dropFirst()).joined(separator: "_")
    }

    static func word(_ key: String, environment: [String: String], plist: (String) -> String?) -> String {
        if let said = environment[name(key)] { return said }
        return plist(key) ?? ""
    }

    static func word(_ key: String) -> String {
        word(key, environment: ProcessInfo.processInfo.environment) { Bundle.main.object(forInfoDictionaryKey: $0) as? String }
    }
}

/// What the config says of the workspace.
struct WorkspaceWords {
    var start = ""              // the start script
    var stop = ""               // the stop script
    var words: [String] = []    // what is said after the start's name (the genes it serves, its own last word)
    var said: [String: String] = [:] // the environment both scripts are given
    var port = 0                // the port that answers on 127.0.0.1
    var pid = ""                // the file the start keeps the workspace's pid in
    var log = ""                // the engines' log, followed into a launch's folder
    var accounts = ""           // the file of the pad's person, which must be there ("": none is asked for)
    var logs = ""               // where each launch's folder is made

    init() {}

    init(_ word: (String) -> String) {
        start = word("InspoWorkspaceStart")
        stop = word("InspoWorkspaceStop")
        words = word("InspoWorkspaceWords").split(separator: " ").map(String.init)
        for pair in word("InspoWorkspaceSaid").split(separator: " ") {
            guard let at = pair.firstIndex(of: "="), at != pair.startIndex else { continue }
            said[String(pair[..<at])] = String(pair[pair.index(after: at)...])
        }
        port = Int(word("InspoWorkspacePort")) ?? 0
        pid = word("InspoWorkspacePid")
        log = word("InspoWorkspaceLog")
        accounts = word("InspoWorkspaceAccounts")
        logs = word("InspoLogs")
    }

    var address: String { "http://127.0.0.1:\(port)/" }

    /// What is missing, in words for the window; nil when a start may be tried.
    var fault: String? {
        let files = FileManager.default
        if start.isEmpty || !files.fileExists(atPath: start) { return "The workspace's start is not there: \(start.isEmpty ? "(INSPO_DESKTOP_WORKSPACE_START says none)" : start)" }
        if stop.isEmpty || !files.fileExists(atPath: stop) { return "The workspace's stop is not there: \(stop.isEmpty ? "(INSPO_DESKTOP_WORKSPACE_STOP says none)" : stop)" }
        if port < 1 || port > 65535 { return "INSPO_DESKTOP_WORKSPACE_PORT is no port." }
        if pid.isEmpty { return "INSPO_DESKTOP_WORKSPACE_PID names no file." }
        if !accounts.isEmpty && !files.fileExists(atPath: accounts) { return "The file of the pad's person is not there: \(accounts)" }
        return nil
    }

    /// What the two scripts are run with: what the app was given, the tools'
    /// own places (an app started from the Dock has a bare PATH), and what
    /// the config says to them.
    func environment(_ base: [String: String]) -> [String: String] {
        var env = base
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for (name, value) in said { env[name] = value }
        return env
    }
}

/// What a launch finds of a workspace that is already up.
enum Standing: Equatable {
    case none                       // nothing is up: start
    case ofAnEarlierLaunch(Int32)   // this app started it and did not quit (it was killed): stop it, then start
    case ofAnotherStart(Int32)      // up, and not started by this app: never stopped unless the person says so
}

/// One launch's run of the workspace: what stands, the start, the stop.
/// Never two at once: a start is run only when nothing stands, and the app
/// stops a workspace only by the stop script, which itself says whether
/// what it finds is that workspace's.
final class WorkspaceRun {
    let words: WorkspaceWords
    let folder: String          // this launch's folder of logs
    private let base: [String: String]
    private(set) var startedHere = false
    private var follower: LogFollower?
    private let one = NSRecursiveLock() // a start and a stop are never run across each other

    init(_ words: WorkspaceWords, folder: String, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.words = words
        self.folder = folder
        base = environment
    }

    /// The note of the workspace this app started and has not stopped: the
    /// pid the start kept, and the launch's folder. Beside the launches.
    var note: String { words.logs + "/standing.json" }

    /// The pid the start's file names, when a process of that pid lives.
    func livePid() -> Int32? {
        guard let text = try? String(contentsOfFile: words.pid, encoding: .utf8),
              let pid = Int32(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 1 else { return nil }
        return kill(pid, 0) == 0 || errno == EPERM ? pid : nil
    }

    private func noted() -> (pid: Int32, launch: String)? {
        guard let data = FileManager.default.contents(atPath: note),
              let read = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let pid = read["pid"] as? Int else { return nil }
        return (Int32(pid), read["launch"] as? String ?? "")
    }

    /// The folder of the launch that started what stands, where it is known.
    var earlierLaunch: String { noted()?.launch ?? "" }

    func standing() -> Standing {
        guard let pid = livePid() else { return .none }
        return noted()?.pid == pid ? .ofAnEarlierLaunch(pid) : .ofAnotherStart(pid)
    }

    /// Runs the start and waits for its end. Zero: the workspace answers (the
    /// start's own wait), and the engines' log is followed from then on.
    @discardableResult
    func start() -> Int32 {
        one.lock()
        defer { one.unlock() }
        guard livePid() == nil else { return -1 } // never two at once
        let follower = LogFollower(from: words.log, to: folder + "/engines.log")
        follower.begin()
        self.follower = follower
        let code = Self.run(words.start, words.words, words.environment(base), into: folder + "/start.log")
        if code == 0, let pid = livePid() {
            startedHere = true
            let said: [String: Any] = ["pid": Int(pid), "launch": folder, "port": words.port]
            try? JSONSerialization.data(withJSONObject: said).write(to: URL(fileURLWithPath: note))
        }
        return code
    }

    /// Runs the stop and waits for its end; `into` is the file its words are
    /// kept in. The note goes when nothing of that pid lives any more.
    @discardableResult
    func stop(into name: String = "stop.log") -> Int32 {
        one.lock()
        defer { one.unlock() }
        let code = Self.run(words.stop, [], words.environment(base), into: folder + "/" + name)
        follower?.end()
        follower = nil
        if livePid() == nil {
            try? FileManager.default.removeItem(atPath: note)
            startedHere = false
        }
        return code
    }

    /// At quit: the workspace this launch started is stopped by the stop (a
    /// start still under way is waited for first); one it did not start is
    /// left as it is, and nil is said.
    func quit() -> Int32? {
        one.lock()
        defer { one.unlock() }
        return startedHere ? stop() : nil
    }

    /// Stops a workspace this launch did not start (an earlier launch's, or
    /// another start's when the person said so), and keeps the engines' log
    /// as it then stands, whole, before a start makes it again.
    @discardableResult
    func stopWhatStood() -> Int32 {
        let code = stop(into: "stop-of-what-stood.log")
        try? FileManager.default.copyItem(atPath: words.log, toPath: folder + "/engines-of-what-stood.log")
        return code
    }

    /// What a start or a stop said last, for the window.
    func lastLines(of name: String, _ most: Int = 12) -> String {
        Self.lastLines(ofFile: folder + "/" + name, most)
    }

    static func lastLines(ofFile path: String, _ most: Int) -> String {
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return text.split(separator: "\n", omittingEmptySubsequences: true).suffix(most).joined(separator: "\n")
    }

    /// Runs a script with /bin/sh, its words and its environment, both its
    /// outputs kept in one file; its exit code, or 127 when it did not run.
    static func run(_ script: String, _ words: [String], _ environment: [String: String], into log: String) -> Int32 {
        FileManager.default.createFile(atPath: log, contents: nil)
        guard let out = FileHandle(forWritingAtPath: log) else { return 127 }
        defer { try? out.close() }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = [script] + words
        p.environment = environment
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = out
        p.standardError = out
        do { try p.run() } catch {
            out.write(Data("the script did not run: \(error.localizedDescription)\n".utf8))
            return 127
        }
        p.waitUntilExit()
        return p.terminationStatus
    }
}

/// A launch's folder of logs: one for each launch, named by its time, and
/// never one that is there already.
enum LaunchLogs {
    static func name(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return "launch-" + f.string(from: date)
    }

    /// Makes the folder and says its path; nil when it could not be made.
    static func begin(root: String, at date: Date = Date()) -> String? {
        guard !root.isEmpty else { return nil }
        let files = FileManager.default
        var path = root + "/" + name(date)
        var n = 2
        while files.fileExists(atPath: path) {
            path = root + "/" + name(date) + "-\(n)"
            n += 1
        }
        do { try files.createDirectory(atPath: path, withIntermediateDirectories: true) } catch { return nil }
        return path
    }
}

/// Lines written to one file of a launch's folder, each with its time.
final class LogFile {
    private let queue = DispatchQueue(label: "inspo.desktop.log")
    private let handle: FileHandle?
    private let time: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    init(_ path: String) {
        FileManager.default.createFile(atPath: path, contents: nil)
        handle = FileHandle(forWritingAtPath: path)
    }

    func line(_ text: String) {
        let now = Date()
        queue.async { [self] in
            handle?.write(Data("\(time.string(from: now)) \(text.replacingOccurrences(of: "\n", with: "\n    "))\n".utf8))
        }
    }

    /// Everything said so far is in the file when this returns.
    func settle() { queue.sync {} }
}

/// Follows a file another process writes (the engines' log) into a launch's
/// folder as it grows, so the folder is whole when the app is killed. The
/// file as it stood before the start is an earlier sitting's and is not
/// copied: the start makes it again, and from then it is this launch's from
/// its first byte.
final class LogFollower {
    private let from: String
    private let to: String
    private let queue = DispatchQueue(label: "inspo.desktop.follow")
    private var timer: DispatchSourceTimer?
    private var before: (size: UInt64, modified: Date)?
    private var ours = false
    private var offset: UInt64 = 0

    init(from: String, to: String) {
        self.from = from
        self.to = to
    }

    private func stands() -> (size: UInt64, modified: Date)? {
        guard !from.isEmpty, let a = try? FileManager.default.attributesOfItem(atPath: from),
              let size = a[.size] as? UInt64, let modified = a[.modificationDate] as? Date else { return nil }
        return (size, modified)
    }

    func begin() {
        queue.sync {
            before = stands()
            FileManager.default.createFile(atPath: to, contents: nil)
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 0.25, repeating: 0.25)
            t.setEventHandler { [weak self] in self?.look() }
            t.resume()
            timer = t
        }
    }

    /// Looks once more, then follows no further.
    func end() {
        queue.sync {
            look()
            timer?.cancel()
            timer = nil
        }
    }

    /// Looks now (a check asks; the timer does the same).
    func lookNow() { queue.sync { look() } }

    private func look() {
        guard let now = stands() else { return }
        if !ours {
            if let before, before.size == now.size, before.modified == now.modified { return }
            ours = true
            offset = 0
        }
        if now.size < offset { offset = 0 } // made again while it was followed
        guard now.size > offset, let file = FileHandle(forReadingAtPath: from), let out = FileHandle(forWritingAtPath: to) else { return }
        defer { try? file.close(); try? out.close() }
        try? file.seek(toOffset: offset)
        let data = file.readDataToEndOfFile()
        _ = try? out.seekToEnd()
        out.write(data)
        offset += UInt64(data.count)
    }
}
