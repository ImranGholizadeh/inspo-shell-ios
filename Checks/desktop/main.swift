// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of Desktop/Workspace.swift and Desktop/PageLog.swift on this Mac,
// with no window, no engine and no port: the config's words, a launch's
// folder of logs, what a launch does with a workspace that is already up,
// the start and the stop run as stand-in scripts that keep a pid as the
// standing ones do, the engines' log followed, and what the page's log
// keeps: scripts/check-desktop.sh.

import Foundation
import JavaScriptCore

var passed = 0, failed = 0
func check(_ name: String, _ ok: Bool, _ got: Any = "") {
    if ok { passed += 1 } else { failed += 1; print("FAIL \(name): \(got)") }
}

let files = FileManager.default
let tmp = NSTemporaryDirectory() + "desktop-check-\(ProcessInfo.processInfo.processIdentifier)"
try! files.createDirectory(atPath: tmp + "/state", withIntermediateDirectories: true)
defer { try? files.removeItem(atPath: tmp) }
func write(_ path: String, _ text: String) { try! text.write(toFile: path, atomically: true, encoding: .utf8) }
func read(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }

// the words
check("a plist key's name in the environment", DesktopWords.name("InspoWorkspaceStart") == "INSPO_DESKTOP_WORKSPACE_START", DesktopWords.name("InspoWorkspaceStart"))
check("a one-word key's name", DesktopWords.name("InspoLogs") == "INSPO_DESKTOP_LOGS" && DesktopWords.name("InspoOpens") == "INSPO_DESKTOP_OPENS")
check("the environment's word is taken before the plist's", DesktopWords.word("InspoWorkspacePort", environment: ["INSPO_DESKTOP_WORKSPACE_PORT": "8201"]) { _ in "6951" } == "8201")
check("the plist's word where the environment says none", DesktopWords.word("InspoWorkspacePort", environment: [:]) { _ in "6951" } == "6951")
check("an empty word in the environment is a word said", DesktopWords.word("InspoWorkspaceAccounts", environment: ["INSPO_DESKTOP_WORKSPACE_ACCOUNTS": ""]) { _ in "/a/file" } == "")

// stand-in scripts: the start keeps the pid of a process that stays, as the
// standing start does, and writes the engines' log anew; the stop ends it
write(tmp + "/start.sh", """
[ -n "$FAILS" ] && { echo "line one"; echo "the port is taken. Nothing was started."; exit 2; }
echo "said: $* port=$SAID_PORT path=$PATH" 
echo "engine: first line of this sitting" > "$THING/serve.log"
nohup sleep 300 > /dev/null 2>&1 &
echo $! > "$THING/pid"
echo "engine: it answers" >> "$THING/serve.log"
""")
write(tmp + "/stop.sh", """
[ -f "$THING/pid" ] || { echo "nothing of it is running"; exit 0; }
kill "$(cat "$THING/pid")" 2>/dev/null; rm -f "$THING/pid"; echo "stopped"; echo "engine: last line" >> "$THING/serve.log"
""")
func words(_ more: [String: String] = [:]) -> WorkspaceWords {
    var plist = ["InspoWorkspaceStart": tmp + "/start.sh", "InspoWorkspaceStop": tmp + "/stop.sh", "InspoWorkspaceWords": "/a/gene /another/gene",
                 "InspoWorkspaceSaid": "THING=\(tmp)/state SAID_PORT=8201 EMPTY=", "InspoWorkspacePort": "8201", "InspoWorkspacePid": tmp + "/state/pid",
                 "InspoWorkspaceLog": tmp + "/state/serve.log", "InspoWorkspaceAccounts": "", "InspoLogs": tmp + "/logs"]
    for (k, v) in more { plist[k] = v }
    return WorkspaceWords { plist[$0] ?? "" }
}
let w = words()
check("the start's words are the config's, in order", w.words == ["/a/gene", "/another/gene"], w.words)
check("what is said to the scripts", w.said == ["THING": tmp + "/state", "SAID_PORT": "8201", "EMPTY": ""], w.said)
check("the address is the port's on this Mac", w.address == "http://127.0.0.1:8201/", w.address)
check("the scripts' environment keeps what the app was given and adds what is said", w.environment(["HOME": "/h", "SAID_PORT": "1"]) ["HOME"] == "/h" && w.environment(["SAID_PORT": "1"])["SAID_PORT"] == "8201")
check("the scripts find the system's tools", (w.environment([:])["PATH"] ?? "").contains("/usr/sbin"))
check("words that are whole have no fault", w.fault == nil, w.fault ?? "")
check("a start that is not there is said", (words(["InspoWorkspaceStart": tmp + "/none.sh"]).fault ?? "").contains("none.sh"))
check("a stop that is not there is said", (words(["InspoWorkspaceStop": ""]).fault ?? "").contains("INSPO_DESKTOP_WORKSPACE_STOP"))
check("a port that is none is said", words(["InspoWorkspacePort": "none"]).fault != nil && words(["InspoWorkspacePort": "70000"]).fault != nil)
check("no pid file named is said", words(["InspoWorkspacePid": ""]).fault != nil)
check("a person's file that is named and not there is said", (words(["InspoWorkspaceAccounts": tmp + "/no-person.json"]).fault ?? "").contains("no-person.json"))

// a launch's folder
let noon = Date(timeIntervalSince1970: 1_791_867_600)
let first = LaunchLogs.begin(root: tmp + "/logs", at: noon) ?? ""
let second = LaunchLogs.begin(root: tmp + "/logs", at: noon) ?? ""
let third = LaunchLogs.begin(root: tmp + "/logs", at: noon) ?? ""
check("a launch's folder is named by its time", first.hasSuffix("/logs/" + LaunchLogs.name(noon)) && LaunchLogs.name(noon).hasPrefix("launch-2026-10-13-"), first)
check("a launch of the same second has a folder of its own", second == first + "-2" && third == first + "-3" && files.fileExists(atPath: second), [second, third])
check("no folder where no place is said", LaunchLogs.begin(root: "") == nil)

// one launch: nothing stands, the start, the engines' log followed, the quit
let env = ProcessInfo.processInfo.environment
write(tmp + "/state/serve.log", "engine: a line of an EARLIER sitting\n")
let one = WorkspaceRun(w, folder: first, environment: env)
check("nothing stands at first", one.standing() == .none, one.standing())
check("the start ends well", one.start() == 0, read(first + "/start.log"))
check("the start was given its words, and what the config says to it", read(first + "/start.log").contains("said: /a/gene /another/gene port=8201"), read(first + "/start.log"))
let pid = one.livePid() ?? 0
check("the workspace's pid is the one the start kept, alive", pid > 1 && read(tmp + "/state/pid").trimmingCharacters(in: .whitespacesAndNewlines) == "\(pid)")
check("this launch started it", one.startedHere)
check("a second start is not run while one stands", one.start() == -1 && one.livePid() == pid)
Thread.sleep(forTimeInterval: 0.7)
check("the engines' log of this sitting is in the launch's folder as it grows", read(first + "/engines.log") == "engine: first line of this sitting\nengine: it answers\n", read(first + "/engines.log"))
check("an earlier sitting's lines are not", !read(first + "/engines.log").contains("EARLIER"))

// (ii) a second launch while that one is up: it is this app's own (the app was killed)
let two = WorkspaceRun(w, folder: second, environment: env)
check("a workspace this app started and did not stop is known as an earlier launch's", two.standing() == .ofAnEarlierLaunch(pid), two.standing())
check("the earlier launch's folder is known", two.earlierLaunch == first, two.earlierLaunch)
check("it is stopped by the stop, and its log kept whole", two.stopWhatStood() == 0 && two.livePid() == nil && kill(pid, 0) != 0 && read(second + "/stop-of-what-stood.log").contains("stopped") && read(second + "/engines-of-what-stood.log").hasSuffix("engine: last line\n"), read(second + "/stop-of-what-stood.log"))
check("then nothing stands, and the start is run", two.standing() == .none && two.start() == 0 && two.startedHere)
let pid2 = two.livePid() ?? 0
check("one workspace, and another than before", pid2 > 1 && pid2 != pid)
check("the quit stops what this launch started", two.quit() == 0 && two.livePid() == nil && kill(pid2, 0) != 0 && !two.startedHere && !files.fileExists(atPath: two.note))
Thread.sleep(forTimeInterval: 0.1)
check("the engines' log has its last line when the stop has ended", read(second + "/engines.log").hasSuffix("engine: last line\n"), read(second + "/engines.log"))

// (ii) a workspace this app did not start (a start from a terminal)
let other = Process()
other.executableURL = URL(fileURLWithPath: "/bin/sleep")
other.arguments = ["300"]
try! other.run()
write(tmp + "/state/pid", "\(other.processIdentifier)\n")
let three = WorkspaceRun(w, folder: third, environment: env)
check("a workspace this app did not start is known as another start's", three.standing() == .ofAnotherStart(other.processIdentifier), three.standing())
check("the quit leaves it as it is", three.quit() == nil && kill(other.processIdentifier, 0) == 0 && read(tmp + "/state/pid").contains("\(other.processIdentifier)"))
check("no start is run beside it", three.start() == -1 && kill(other.processIdentifier, 0) == 0)
check("the person's word stops it by the stop, and the start is then run", three.stopWhatStood() == 0 && three.livePid() == nil && three.start() == 0 && three.startedHere)
other.waitUntilExit()
check("and the quit stops that one", three.quit() == 0 && three.livePid() == nil)
write(tmp + "/state/pid", "999999\n")
check("a pid file that names no live process is no workspace", three.standing() == .none)

// a start that fails: its last lines are for the window
var failing = env
failing["FAILS"] = "1"
let fourth = LaunchLogs.begin(root: tmp + "/logs") ?? ""
try? files.removeItem(atPath: tmp + "/state/pid")
let four = WorkspaceRun(w, folder: fourth, environment: failing)
check("a start that fails says its code", four.start() == 2 && !four.startedHere && four.quit() == nil)
check("and its last lines are kept for the window", four.lastLines(of: "start.log", 1) == "the port is taken. Nothing was started." && four.lastLines(of: "start.log").hasPrefix("line one"), four.lastLines(of: "start.log"))

// the follower by itself: a file made again while it is followed
write(tmp + "/f.log", "old\n")
let follower = LogFollower(from: tmp + "/f.log", to: tmp + "/f.kept")
follower.begin()
follower.lookNow()
check("a file as it stood before is not copied", read(tmp + "/f.kept") == "")
write(tmp + "/f.log", "new one\n")
follower.lookNow()
let more = FileHandle(forWritingAtPath: tmp + "/f.log")!
more.seekToEndOfFile(); more.write(Data("new two\n".utf8)); try? more.close()
follower.lookNow()
check("what is written from then on is, as it grows", read(tmp + "/f.kept") == "new one\nnew two\n", read(tmp + "/f.kept"))
write(tmp + "/f.log", "again\n")
follower.end()
check("a file made again is followed from its first byte", read(tmp + "/f.kept") == "new one\nnew two\nagain\n", read(tmp + "/f.kept"))

// a log file's lines
let log = LogFile(tmp + "/app.log")
log.line("one"); log.line("two\nlines"); log.settle()
let lines = read(tmp + "/app.log").split(separator: "\n").map(String.init)
check("each line has its time, and a second line of one saying is set in", lines.count == 3 && lines[0].hasSuffix(" one") && lines[0].count == 16 && lines[2] == "    lines", lines)

// the page's log: what the page says to its console and what nobody caught, and no field
let js = JSContext()!
var said: [[String: Any]] = []
let post: @convention(block) (JSValue) -> Void = { said.append($0.toDictionary() as? [String: Any] ?? [:]) }
js.setObject(post, forKeyedSubscript: "post" as NSString)
js.evaluateScript("""
var heard = {}; var window = this; window.addEventListener = function (name, f) { heard[name] = f };
var console = { log: function () {}, info: function () {}, warn: function () {}, error: function () {}, debug: function () {} };
window.webkit = { messageHandlers: { \(PageLog.handler): { postMessage: post } } };
""")
js.evaluateScript(PageLog.script)
js.evaluateScript(#"console.log("drawn", {n: 2}); console.error(new Error("broke")); heard.error({message: "ReferenceError: x", filename: "app.js", lineno: 3, colno: 9}); heard.unhandledrejection({reason: "refused"});"#)
let kept = said.compactMap { PageLog.line($0) }
check("the console's line is kept with its level", kept.first == #"log: drawn {"n":2}"#, kept)
check("an error said to the console is kept", kept.count == 4 && kept[1].hasPrefix("error: ") && kept[1].contains("broke"), kept)
check("an error nobody caught is kept with its place", kept.count == 4 && kept[2].hasPrefix("uncaught: ReferenceError: x app.js:3:9"), kept)
check("a promise nobody answered is kept", kept.last == "unanswered: refused", kept)
let listened = (js.evaluateScript("Object.keys(heard).sort().join(' ')").toString()) ?? ""
check("the page's log listens to an error and an unanswered promise, and to no field and no key", listened == "error unhandledrejection", listened)
check("what is no message of the page's is no line", PageLog.line("text") == nil && PageLog.line(["level": "log"]) == nil)
js.evaluateScript(PageLog.script)
js.evaluateScript(#"console.log("once")"#)
check("set twice, it says a line once", said.count == 5, said.count)

print("desktop: \(passed) passed, \(failed) failed")
exit(failed == 0 ? 0 : 1)
