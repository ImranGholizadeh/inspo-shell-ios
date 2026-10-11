// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

// A check of the shell's push library (Shell/Push.swift) on this Mac, with
// a phone that only records what it was asked and says what the check has
// it say, and a clock the check moves: scripts/check-push.sh.

import Foundation

/// A clock the check moves: work waits until its time is passed.
final class Clock {
    private(set) var now = 0.0
    private var count = 0
    private var waiting: [(at: Double, id: Int, work: () -> Void)] = []

    func wait(_ seconds: TimeInterval, _ work: @escaping () -> Void) -> () -> Void {
        count += 1
        let id = count
        waiting.append((now + seconds, id, work))
        return { [weak self] in self?.waiting.removeAll { $0.id == id } }
    }

    func pass(_ seconds: Double) {
        let end = now + seconds
        while let next = waiting.filter({ $0.at <= end }).min(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            waiting.removeAll { $0.id == next.id }
            now = next.at
            next.work()
        }
        now = end
    }
}

/// A phone that only records what it was asked. The person says what the
/// check has them say, once, the first time they are asked; Apple answers
/// when the check has it answer.
final class RecordedPhone: PushPhone {
    var asked: [String] = []
    var said = PushPermission.notAsked
    var personSays = PushPermission.allowed
    var environment = PushEnvironment.development
    var app = "com.example.made-up-app"
    private var registering: [(Result<Data, NativeError>) -> Void] = []

    func permission(_ done: @escaping (PushPermission) -> Void) {
        asked.append("read")
        done(said)
    }
    func askPermission(_ done: @escaping (PushPermission) -> Void) {
        asked.append("ask")
        if said == .notAsked { said = personSays } // iOS asks once
        done(said)
    }
    func registerWithApple(_ done: @escaping (Result<Data, NativeError>) -> Void) {
        asked.append("register")
        registering.append(done)
    }
    /// Apple answers every registration that waits.
    func apple(_ result: Result<Data, NativeError>) {
        let waiting = registering
        registering = []
        waiting.forEach { $0(result) }
    }
}

/// An event or an answer with every field: key=value, in the keys' order.
func fields(_ value: [String: Any]) -> String {
    value.isEmpty ? "{}" : value.keys.sorted().map { "\($0)=\(value[$0]!)" }.joined(separator: " ")
}

/// The library over a recorded phone, with the clock, and what was answered.
final class Bench {
    let clock = Clock()
    let phone = RecordedPhone()
    let library: PushLibrary
    /// every call's answer, in the order they came
    var answered: [String] = []

    init() {
        library = PushLibrary(phone: phone)
        library.wait = clock.wait
        library.now = { [clock] in clock.now }
    }

    func call(_ name: String, _ data: Any? = nil) {
        library.call(name, data: data) { result in
            switch result {
            case .success(let value): self.answered.append(fields(value))
            case .failure(let err): self.answered.append("error: \(err.message)")
            }
        }
    }

    /// Opens a stream; what it hears is written into the list returned.
    func open(_ events: String = "events") -> (heard: () -> [String], stop: () -> Void) {
        var heard: [String] = []
        let stop = library.listen(events, data: nil, each: { heard.append(fields($0)) }, failed: { heard.append("failed: \($0.message)") })
        return ({ heard }, stop)
    }
}

var passed = 0, failed = 0
func check(_ name: String, _ got: [String], _ want: [String]) {
    if got == want { passed += 1 } else { failed += 1; print("FAIL \(name):\n  got  \(got)\n  want \(want)") }
}

let token = Data([0x00, 0x0f, 0xa9, 0xff, 0x10])
let payload: [AnyHashable: Any] = ["aps": ["alert": ["title": "A made-up title", "body": "A made-up body"]],
                                   "link": "made-up-app://open?from=notification", "other": "a made-up word"]

// MARK: nothing by itself

do {
    let bench = Bench()
    let stream = bench.open()
    bench.clock.pass(100)
    check("the library asks the person nothing, and Apple nothing, until a record's call asks", bench.phone.asked + stream.heard(), [])
}

// MARK: the permission call

do {
    let bench = Bench()
    bench.call("permission")
    check("the permission call asks the person, and answers that they allowed it", bench.answered + bench.phone.asked,
          ["permission=allowed", "ask"])
    bench.call("permission")
    check("asked again, the answer they gave comes back", last(bench.answered), ["permission=allowed"])
}

do {
    let bench = Bench()
    bench.phone.personSays = .refused
    bench.call("permission")
    check("a person who refuses is an answer, not a failure", bench.answered, ["permission=refused"])
}

do {
    let bench = Bench()
    bench.call("permission", ["ask": 0])
    check("with ask 0 nothing is asked: a person never asked is not-asked", bench.answered + bench.phone.asked,
          ["permission=not-asked", "read"])
    bench.call("permission", ["ask": 1])
    bench.call("permission", ["ask": 0])
    check("and after they were asked it reads what they said", bench.answered + bench.phone.asked,
          ["permission=not-asked", "permission=allowed", "permission=allowed", "read", "ask", "read"])
    bench.call("permission", "ask")
    bench.call("permission", ["ask": "no"])
    check("data that does not say ask 0 asks, as no data does", Array(bench.phone.asked.suffix(2)), ["ask", "ask"])
    check("the permission call asks Apple for nothing", bench.phone.asked.filter { $0 == "register" }, [])
}

// MARK: the token call

do {
    let bench = Bench()
    bench.call("token")
    check("the token call registers with Apple, and waits for its answer", bench.phone.asked + bench.answered, ["register"])
    bench.phone.apple(.success(token))
    check("it answers Apple's token as small hex, two characters a byte, the environment and the app's id", bench.answered,
          ["app=com.example.made-up-app environment=development token=000fa9ff10"])
    check("and asks the person nothing: a token needs no permission", bench.phone.asked, ["register"])
    bench.clock.pass(100)
    check("a call that was answered is not failed by its limit later", bench.answered.count == 1 ? [] : bench.answered, [])
}

do {
    let bench = Bench()
    bench.phone.environment = .production
    bench.call("token")
    bench.call("token")
    check("two calls that wait together ask Apple once", bench.phone.asked, ["register"])
    bench.phone.apple(.success(token))
    check("and Apple's answer is both's, with the production environment said", bench.answered,
          ["app=com.example.made-up-app environment=production token=000fa9ff10",
           "app=com.example.made-up-app environment=production token=000fa9ff10"])
    bench.call("token")
    check("a call after the answer asks Apple again: the shell kept no token", bench.phone.asked + [String(bench.answered.count)],
          ["register", "register", "2"])
}

do {
    let bench = Bench()
    bench.call("token")
    bench.phone.apple(.failure(NativeError(message: "push: Apple did not register this phone")))
    check("Apple refuses: the call fails, with the reason", bench.answered, ["error: push: Apple did not register this phone"])
}

do {
    let bench = Bench()
    bench.call("token")
    bench.clock.pass(24.9)
    check("Apple says nothing: the call waits under its limit", bench.answered, [])
    bench.clock.pass(0.1)
    check("and fails at 25 seconds, before the engine's own limit", bench.answered, ["error: push: Apple did not answer in time"])
    bench.phone.apple(.success(token))
    check("Apple's answer after that is nobody's", bench.answered, ["error: push: Apple did not answer in time"])
    bench.call("token")
    check("the next call asks Apple again", bench.phone.asked, ["register", "register"])
    bench.phone.apple(.success(Data([0xab])))
    check("and is answered with what Apple says then, never with the answer that came for nobody", last(bench.answered),
          ["app=com.example.made-up-app environment=development token=ab"])
}

do {
    let bench = Bench()
    bench.call("subscribe", ["topics": ["a"]])
    bench.call("")
    check("the library has no other call", bench.answered, ["error: push has no call subscribe", "error: push has no call "])
    check("and such a call asks the phone nothing", bench.phone.asked, [])
}

// MARK: the stream

do {
    let bench = Bench()
    let (one, two) = (bench.open(), bench.open())
    bench.library.tapped(payload)
    check("a tap is said to every open stream, with the notification's link and nothing else of it", one.heard() + two.heard(),
          ["kind=tap link=made-up-app://open?from=notification", "kind=tap link=made-up-app://open?from=notification"])
    one.stop()
    bench.library.tapped(["link": 5, "aps": ["alert": "words"]])
    bench.library.tapped(["link": ""])
    bench.library.tapped([:])
    check("a notification with no link, or one that is no text, is a tap with none; a stream that was stopped hears nothing more",
          [String(one.heard().count)] + Array(two.heard().dropFirst()), ["1", "kind=tap", "kind=tap", "kind=tap"])
    let late = bench.open()
    check("a tap that was said is not said again to a stream that opens later", late.heard(), [])
    check("a tap asks the phone nothing", bench.phone.asked, [])
}

do {
    let bench = Bench()
    bench.library.tapped(["link": "made-up-app://first"])
    bench.library.tapped(payload)
    let first = bench.open()
    let second = bench.open()
    check("a tap that comes with no stream open (it opened an app that was closed) is kept, the last one only, and said to the first stream that opens, once",
          first.heard() + second.heard(), ["kind=tap link=made-up-app://open?from=notification"])
    first.stop()
    second.stop()
    let third = bench.open()
    check("and never again", third.heard(), [])
}

do {
    let bench = Bench()
    let old = bench.open()
    bench.library.tapped(payload)
    bench.clock.pass(2)
    bench.library.pageGone()
    old.stop()
    let loaded = bench.open()
    check("a page that goes within three seconds of a tap may not have taken it: the tap is kept again, and said to the page that loads",
          old.heard() + loaded.heard(), ["kind=tap link=made-up-app://open?from=notification", "kind=tap link=made-up-app://open?from=notification"])
    bench.clock.pass(3.1)
    bench.library.pageGone()
    loaded.stop()
    let later = bench.open()
    check("a page that goes later than that had it: the tap is not said again", later.heard(), [])
    bench.library.pageGone()
    let none = bench.open()
    check("and a page that goes with no tap said has none kept", none.heard(), [])
}

do {
    let bench = Bench()
    bench.library.tapped(payload)
    let first = bench.open()
    bench.clock.pass(1)
    bench.library.pageGone()
    first.stop()
    check("a kept tap said to the first page, when that page goes within three seconds, is kept again too",
          first.heard() + bench.open().heard(), ["kind=tap link=made-up-app://open?from=notification", "kind=tap link=made-up-app://open?from=notification"])
}

do {
    // one tap, and fifty pages that each go a second after they hear it
    func pages(_ bench: Bench, _ first: (heard: () -> [String], stop: () -> Void)) -> [Int] {
        var page = first, heard: [Int] = []
        for _ in 0..<50 {
            heard.append(page.heard().count)
            bench.clock.pass(1)
            bench.library.pageGone()
            page.stop()
            page = bench.open()
        }
        return heard
    }
    let warm = Bench()
    let open = warm.open()
    warm.library.tapped(payload)
    let said = pages(warm, open)
    check("a tap said to a page that goes is kept for the next page once and not again: of fifty pages that each go as they hear it, the first two hear it and no other",
          [String(said.reduce(0, +)), String(said.prefix(2).reduce(0, +))], ["2", "2"])
    let cold = Bench()
    cold.library.tapped(payload) // it opened an app that was closed
    let after = pages(cold, cold.open())
    check("and so for the tap that opened a closed app: the first page and the one after it, no other",
          [String(after.reduce(0, +)), String(after.prefix(2).reduce(0, +))], ["2", "2"])
    let fresh = Bench()
    let stream = fresh.open()
    fresh.library.tapped(payload)
    fresh.clock.pass(1)
    fresh.library.pageGone()
    stream.stop()
    let next = fresh.open()
    fresh.library.tapped(["link": "made-up-app://second"])
    fresh.clock.pass(1)
    fresh.library.pageGone()
    next.stop()
    check("a second tap is a tap of its own: kept again once for the page after, though the tap before it had been",
          next.heard() + fresh.open().heard(),
          ["kind=tap link=made-up-app://open?from=notification", "kind=tap link=made-up-app://second", "kind=tap link=made-up-app://second"])
}

do {
    let bench = Bench()
    let old = bench.open()
    bench.library.tapped(payload)
    old.stop()
    let next = bench.open()
    check("a stream that only closes (its screen was left) is no page going: the tap is not said to the screen that opens",
          next.heard(), [])
}

do {
    let bench = Bench()
    check("a notification that arrives with the app on the screen and no stream open is iOS's to show, and is kept for nobody",
          [String(bench.library.arrived(payload))] + bench.open().heard(), ["false"])
    let stream = bench.open()
    check("with a stream open the page is told, with the link, and iOS shows nothing",
          [String(bench.library.arrived(payload))] + stream.heard(), ["true", "kind=arrived link=made-up-app://open?from=notification"])
}

do {
    let bench = Bench()
    let wrong = bench.open("taps")
    check("the library has no other stream", wrong.heard(), ["failed: push has no stream taps"])
    bench.library.tapped(payload)
    check("and a stream that failed is none: the tap is kept for one that opens", bench.open().heard(),
          ["kind=tap link=made-up-app://open?from=notification"])
}

// MARK: only what keep names leaves the shell

do {
    let bench = Bench()
    NativeLibraries.shared.register(bench.library)
    var kept: [String] = []
    let take: (String, [String: Any]) -> Void = { id, value in kept.append(id + ": " + fields(value)) }
    let fail: (String, String) -> Void = { id, error in kept.append(id + ": error: " + error) }
    NativeLibraries.shared.handle(["id": "p", "url": "native://push/permission", "keep": ["permission"]], answered: take, failed: fail)
    NativeLibraries.shared.handle(["id": "t1", "url": "native://push/token", "keep": ["token", "environment", "app"]], answered: take, failed: fail)
    NativeLibraries.shared.handle(["id": "t2", "url": "native://push/token", "keep": ["environment"]], answered: take, failed: fail)
    NativeLibraries.shared.handle(["id": "t3", "url": "native://push/token", "keep": [String]()], answered: take, failed: fail)
    bench.phone.apple(.success(token))
    NativeLibraries.shared.handle(["id": "s1", "url": "native://push/events", "listen": true, "keep": ["kind", "link"]], answered: take, failed: fail)
    NativeLibraries.shared.handle(["id": "s2", "url": "native://push/events", "listen": true, "keep": ["kind"]], answered: take, failed: fail)
    bench.library.tapped(payload)
    NativeLibraries.shared.stopAll()
    bench.library.tapped(payload)
    check("through the shell's door: the token reaches only a call whose endpoint keeps it, a link only a stream whose endpoint keeps it, and a stopped stream nothing",
          kept.sorted(), ["p: permission=allowed", "s1: kind=tap link=made-up-app://open?from=notification", "s2: kind=tap",
                          "t1: app=com.example.made-up-app environment=development token=000fa9ff10", "t2: environment=development", "t3: {}"])
}

// MARK: the token as a push service takes it

do {
    let long = Data((0..<32).map { UInt8($0 * 8) })
    check("a token of 32 bytes is 64 small hex characters, a zero kept where a byte is small",
          [String(PushLibrary.hex(long).count), String(PushLibrary.hex(long).prefix(8)), PushLibrary.hex(Data())], ["64", "00081018", ""])
}

// MARK: Apple's push environment, from the build's own provisioning profile

/// A provisioning profile as iOS carries one: a signed envelope's bytes
/// around a property list. Made up.
func profile(_ entitlements: String) -> Data {
    var data = Data([0x30, 0x82, 0x1f, 0x00, 0xff, 0x00, 0x3c])
    data.append(Data("""
    <?xml version="1.0" encoding="UTF-8"?>
    <plist version="1.0"><dict><key>Name</key><string>A made-up profile</string>
    <key>Entitlements</key><dict>\(entitlements)</dict></dict></plist>
    """.utf8))
    data.append(Data([0xa0, 0x82, 0x00, 0xfe, 0x3c, 0x2f]))
    return data
}

do {
    let said = [
        PushEnvironment.of(profile: profile("<key>aps-environment</key><string>development</string>"), simulator: false),
        PushEnvironment.of(profile: profile("<key>aps-environment</key><string>production</string>"), simulator: false),
        PushEnvironment.of(profile: nil, simulator: false),
        PushEnvironment.of(profile: profile("<key>get-task-allow</key><true/>"), simulator: false),
        PushEnvironment.of(profile: Data([0x00, 0x01, 0x02]), simulator: false),
        PushEnvironment.of(profile: profile("<key>aps-environment</key><string>production</string>"), simulator: true),
    ].map(\.rawValue)
    check("the environment is the build's own profile's: development, production; a build with no profile (the App Store's, TestFlight's) is production, and so is a profile that does not say or cannot be read; a simulator's is development whatever it carries",
          said, ["development", "production", "production", "production", "production", "development"])
}

// MARK: what the sources hold to

do {
    let library = (try? String(contentsOfFile: "Shell/Push.swift", encoding: .utf8)) ?? ""
    let phone = (try? String(contentsOfFile: "Shell/PhonePush.swift", encoding: .utf8)) ?? ""
    check("the sources are read", [String(library.isEmpty), String(phone.isEmpty)], ["false", "false"])
    check("the library prints nothing and keeps nothing: no defaults, no file",
          ["print(", "UserDefaults", "FileManager", ".write(", "NSLog", "Logger"].filter(library.contains), [])
    let printed = phone.split(separator: "\n").filter { $0.contains("print(") }
    check("the phone's part keeps nothing, and no line it prints holds a token or anything of a notification",
          ["UserDefaults", "FileManager", ".write(", "NSLog", "Logger"].filter(phone.contains)
              + printed.filter { line in ["oken", "userInfo", "payload", "content", "link"].contains { line.contains($0) } }.map(String.init), [])
    // no third party's code: what the two files import is Apple's own, and
    // the project and its packages fetch no package from anywhere
    let imports = (library + "\n" + phone).split(separator: "\n").filter { $0.hasPrefix("import ") }.map(String.init)
    check("push imports Apple's own frameworks alone", imports.sorted(), ["import Foundation", "import UIKit", "import UserNotifications"])
    let project = (try? String(contentsOfFile: "Shell.xcodeproj/project.pbxproj", encoding: .utf8)) ?? ""
    let packages = ["Packages/IDScannerSurface/Package.swift", "Packages/IDScannerBinding/Package.swift"]
        .map { (try? String(contentsOfFile: $0, encoding: .utf8)) ?? "url:" }
    let folders = ((try? FileManager.default.contentsOfDirectory(atPath: "Packages")) ?? []).filter { !$0.hasPrefix(".") }.sorted()
    check("the project fetches no package from anywhere, and holds the two packages it held",
          [String(project.contains("XCRemoteSwiftPackageReference")), String(packages.contains { $0.contains("url:") })] + folders,
          ["false", "false", "IDScannerBinding", "IDScannerSurface"])
}

// MARK: the push environment a build signed on a Mac asks

do {
    // a build signed here (a simulator's, one run from Xcode, an archive) is
    // signed with the team's development profile, whose push environment
    // is development: an entitlements file that asks production does not
    // match it. The upload's export signs again and writes production.
    let config = (try? String(contentsOfFile: "Config/Default.xcconfig", encoding: .utf8)) ?? ""
    let said = config.split(separator: "\n").filter { $0.hasPrefix("INSPO_PUSH_ENVIRONMENT") }.map { $0.replacingOccurrences(of: " ", with: "") }
    check("the push environment a build asks, unless its lane says another, is development", said, ["INSPO_PUSH_ENVIRONMENT=development"])
    let file = (try? String(contentsOfFile: "Config/Push.entitlements", encoding: .utf8)) ?? ""
    check("and the entitlements file asks the one the build says, never one of its own",
          [String(file.contains("<key>aps-environment</key>\n\t<string>$(INSPO_PUSH_ENVIRONMENT)</string>"))], ["true"])
}

func last(_ list: [String]) -> [String] { Array(list.suffix(1)) }

print("push: \(passed) passed, \(failed) failed")
if failed > 0 { exit(1) }
