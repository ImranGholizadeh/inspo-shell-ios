// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation

// Push on the phone, as a native library a gene reaches through the exotic
// bridge like any other (NativeLibrary.swift): three things only the phone
// can do, each done when a record's native call asks for it and never
// before. The shell asks the person nothing, registers with nobody and
// hands no token over at launch or by itself.
//
//   calls   permission   asks the person whether this app may notify them,
//                        and answers what they said: { permission:
//                        "allowed" | "refused" }. iOS shows its question the
//                        first time only; after that the answer it was
//                        given comes back with no question. With data
//                        {ask: 0} nothing is asked: it answers at once what
//                        the person has said so far, "not-asked" when they
//                        have never been asked.
//           token        registers this phone with Apple and answers
//                        { token, environment, app }: the phone's push
//                        token as Apple gave it (small hex letters and
//                        digits), Apple's push environment this build is
//                        signed for ("development" or "production"), and
//                        the app's own id (its bundle identifier): the
//                        three a push service must be told to reach this
//                        phone. It needs no permission: a phone whose
//                        person refused has a token too, and is shown
//                        nothing. Apple hands a phone a new token now and
//                        then (a restore, a new install): a gene asks for
//                        it each time its page arrives. With no answer of
//                        Apple's in 25 seconds (a phone with no network
//                        hears nothing from Apple, neither way) the call
//                        fails.
//   stream  events       every event, flat, with a kind:
//
//   { kind: "tap", link }      the person tapped a notification of this
//                              app; link is the notification's own link
//                              (its payload's link, a text), when it has
//                              one. A tap that opens an app that was closed
//                              comes before any page has asked: it is kept,
//                              the last one only, and said to the first
//                              stream that opens
//   { kind: "arrived", link }  a notification arrived while the app is on
//                              the screen and a stream is open: the page is
//                              told and draws what it will, and iOS shows
//                              nothing over it. With no stream open nobody
//                              would tell the person, so iOS shows it as it
//                              does with the app behind
//
// Nothing of a push service is here: no package of one, no address, no
// name. What a service needs beyond the three answers (its own token for
// this phone, a topic the phone joins or leaves) is a call the gene's
// records make through the engine, which the deployment signs; the phone
// only says who it is to Apple. A notification that arrives with the app
// behind or closed is shown by iOS itself, with nothing of the shell
// running.
//
// The token is the phone's own name at Apple: the shell keeps it nowhere
// (no file, no defaults, no log), and hands it to the page only when the
// endpoint's keep names it. A development build says that a call was
// answered and which fields were handed over, never a value.

/// What the person has said of notifications for this app.
enum PushPermission: String {
    case allowed, refused
    case notAsked = "not-asked"
}

/// The phone's own part of push: the person's answer and Apple's
/// registration. The app's is PhonePush; a check's only records.
protocol PushPhone: AnyObject {
    /// What the person has said so far; nothing is asked.
    func permission(_ done: @escaping (PushPermission) -> Void)
    /// Asks the person whether this app may notify them. iOS shows its
    /// question the first time only. done, once: what they said.
    func askPermission(_ done: @escaping (PushPermission) -> Void)
    /// Registers this phone with Apple. done, once: Apple's token for it,
    /// or why there is none; never, when Apple says nothing.
    func registerWithApple(_ done: @escaping (Result<Data, NativeError>) -> Void)
    /// Apple's push environment this build is signed for.
    var environment: PushEnvironment { get }
    /// The app's own id: its bundle identifier.
    var app: String { get }
}

/// Apple's two push environments. A token is good in one of them only, so
/// whoever sends to it must know which.
enum PushEnvironment: String {
    case development, production

    /// The environment a build is signed for, read from its own
    /// provisioning profile (the file embedded.mobileprovision in the app,
    /// whose entitlements say aps-environment). A build from the App Store
    /// or TestFlight carries no profile and is production; a simulator's
    /// build is development, whatever it carries.
    static func of(profile: Data?, simulator: Bool) -> PushEnvironment {
        if simulator { return .development }
        guard let profile, let said = entitlement("aps-environment", in: profile) else { return .production }
        return said == "development" ? .development : .production
    }

    /// One text entitlement of a provisioning profile: the profile is a
    /// signed envelope around a property list, read from its first <plist
    /// to its last </plist>.
    static func entitlement(_ name: String, in profile: Data) -> String? {
        guard let open = profile.range(of: Data("<plist".utf8)),
              let close = profile.range(of: Data("</plist>".utf8), options: .backwards),
              open.lowerBound < close.upperBound,
              let list = try? PropertyListSerialization.propertyList(from: profile[open.lowerBound..<close.upperBound], format: nil),
              let entitlements = (list as? [String: Any])?["Entitlements"] as? [String: Any] else { return nil }
        return entitlements[name] as? String
    }
}

final class PushLibrary: NativeLibrary {
    let name = "push"
    private let phone: PushPhone
    /// The page's streams, by key; every event reaches each.
    private var sinks: [UUID: ([String: Any]) -> Void] = [:]
    /// A tap that came while no stream was open (the app was closed, or
    /// its page had not asked yet): said to the first stream that opens.
    private var kept: [String: Any]?
    /// The last tap said to the streams, and when: a page that goes within
    /// a moment of it may not have taken it (pageGone).
    private var said: (tap: [String: Any], at: TimeInterval)?
    /// The token calls that wait for Apple.
    private var waiting: [UUID: (Result<[String: Any], NativeError>) -> Void] = [:]

    /// How long Apple may take to answer a registration, in seconds: under
    /// the engine's own limit for a native call (30), so the call fails
    /// here, with its reason.
    static let appleLimit: TimeInterval = 25
    /// How long after a tap was said a page that goes is taken not to have
    /// heard it, in seconds.
    static let heardAfter: TimeInterval = 3

    /// Runs work after some seconds, unless the returned cancel is called
    /// first; and the time now, in seconds. A check passes the time itself.
    static let onMain: (TimeInterval, @escaping () -> Void) -> () -> Void = { seconds, work in
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
        return { item.cancel() }
    }
    var wait = PushLibrary.onMain
    var now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }

    init(phone: PushPhone) {
        self.phone = phone
    }

    // MARK: calls

    func call(_ call: String, data: Any?, answer: @escaping (Result<[String: Any], NativeError>) -> Void) {
        switch call {
        case "permission":
            let said: (PushPermission) -> Void = { answer(.success(["permission": $0.rawValue])) }
            if Self.asks(data) { phone.askPermission(said) } else { phone.permission(said) }
        case "token":
            token(answer)
        default:
            answer(.failure(NativeError(message: "push has no call \(call)")))
        }
    }

    /// Whether a permission call asks the person. It does, unless the
    /// gene's data says {ask: 0}.
    static func asks(_ data: Any?) -> Bool {
        guard let ask = (data as? [String: Any])?["ask"] as? NSNumber else { return true }
        return ask.boolValue
    }

    /// One token call. Apple is asked once for all that wait together,
    /// and its answer is theirs; with no answer in time a call fails, and
    /// the next call asks Apple again. An answer that comes when nobody
    /// waits is nobody's: it is kept nowhere.
    private func token(_ answer: @escaping (Result<[String: Any], NativeError>) -> Void) {
        let key = UUID()
        let first = waiting.isEmpty
        waiting[key] = answer
        _ = wait(Self.appleLimit) { [weak self] in
            self?.waiting.removeValue(forKey: key)?(.failure(NativeError(message: "push: Apple did not answer in time")))
        }
        guard first else { return }
        phone.registerWithApple { [weak self] registered in
            guard let self else { return }
            let all = self.waiting
            self.waiting = [:]
            let result = registered.map { token -> [String: Any] in
                ["token": Self.hex(token), "environment": self.phone.environment.rawValue, "app": self.phone.app]
            }
            all.values.forEach { $0(result) }
        }
    }

    /// Apple's token as a push service takes it: two small hex characters
    /// a byte.
    static func hex(_ token: Data) -> String {
        token.map { byte in
            let pair = String(byte, radix: 16)
            return pair.count == 1 ? "0" + pair : pair
        }.joined()
    }

    // MARK: the stream

    func listen(_ events: String, data: Any?, each: @escaping ([String: Any]) -> Void,
                failed: @escaping (NativeError) -> Void) -> () -> Void {
        guard events == "events" else {
            failed(NativeError(message: "push has no stream \(events)"))
            return {}
        }
        let key = UUID()
        sinks[key] = each
        // a tap nobody has heard: this stream's, as it opens
        if let tap = kept {
            kept = nil
            said = (tap, now())
            each(tap)
        }
        return { [weak self] in self?.sinks.removeValue(forKey: key) }
    }

    /// The person tapped a notification of this app. Said to every open
    /// stream; with none open it is kept for the first that opens.
    func tapped(_ payload: [AnyHashable: Any]) {
        let tap = Self.event("tap", payload)
        guard !sinks.isEmpty else {
            kept = tap
            return
        }
        said = (tap, now())
        sinks.values.forEach { $0(tap) }
    }

    /// A notification arrived with the app on the screen. True when a
    /// stream was told: the page draws it, and iOS shows nothing. False
    /// with no stream open: iOS shows it.
    func arrived(_ payload: [AnyHashable: Any]) -> Bool {
        guard !sinks.isEmpty else { return false }
        let event = Self.event("arrived", payload)
        sinks.values.forEach { $0(event) }
        return true
    }

    /// The page has gone (it loads afresh, or iOS ended its content). A
    /// tap said a moment before may have been said to a page that was
    /// already going: it is kept again, for the page that loads. Called
    /// before the page's streams are stopped.
    func pageGone() {
        guard let last = said else { return }
        said = nil
        if now() - last.at <= Self.heardAfter { kept = last.tap }
    }

    /// An event of a notification: its kind and, when its payload has one
    /// that is a text, its link. Nothing else of a payload is passed on.
    static func event(_ kind: String, _ payload: [AnyHashable: Any]) -> [String: Any] {
        var value: [String: Any] = ["kind": kind]
        if let link = payload["link"] as? String, !link.isEmpty { value["link"] = link }
        return value
    }
}
