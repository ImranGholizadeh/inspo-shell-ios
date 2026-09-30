// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import Foundation
import Darwin

// The Go engine inside the desktop app: the audit binary bundled in the
// app's resources (engine/audit), started as mine-serve on a free loopback
// port, serving the bundled renderer (engine/client) and the page
// (engine/pages/<page>.json) to this app's web view alone. It reads Inspo's
// store with the person's own gcloud sign-in, as the owner's machine does
// for every mine command. It stops when the app quits.
@MainActor
final class EngineHelper: ObservableObject {
    static let shared = EngineHelper()

    @Published private(set) var pageURL: URL?
    @Published private(set) var status = "Starting the engine…"
    private var process: Process?

    private func setting(_ key: String) -> String {
        (Bundle.main.object(forInfoDictionaryKey: key) as? String) ?? ""
    }

    func start() {
        guard process == nil, let res = Bundle.main.resourceURL?.appendingPathComponent("engine") else { return }
        let audit = res.appendingPathComponent("audit")
        guard FileManager.default.isExecutableFile(atPath: audit.path) else {
            status = "The engine is not in this build (engine/audit)."
            return
        }
        guard let port = Self.freePort() else {
            status = "No free local port for the engine."
            return
        }
        let page = setting("InspoPage").isEmpty ? "viewer" : setting("InspoPage")
        let client = ["--client", res.appendingPathComponent("client").path,
                      "--page", "/=" + res.appendingPathComponent("pages/\(page).json").path,
                      "--addr", "127.0.0.1:\(port)"]
        var args: [String]
        let devGene = setting("InspoDevGene")
        if !devGene.isEmpty {
            // a gene in development on this Mac: dev-serve, no cloud, with
            // the local auth stand-in, its test accounts and the gene states
            // the grid lists
            args = ["dev-serve", "--gene", devGene] + client
            if !setting("InspoDevAccounts").isEmpty { args += ["--accounts", setting("InspoDevAccounts")] }
            if !setting("InspoDevStates").isEmpty { args += ["--states", setting("InspoDevStates")] }
        } else {
            args = ["mine-serve", "--project", setting("InspoProject"), "--no-records"] + client
            for db in setting("InspoRead").split(separator: " ") { args += ["--read", String(db)] }
        }
        let p = Process()
        p.executableURL = audit
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        // an app started from the Dock has a bare PATH: gcloud (the
        // person's own sign-in) is looked for where it is installed
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        p.environment = env
        let log = Pipe()
        p.standardOutput = log
        p.standardError = log
        log.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8), !text.isEmpty { FileHandle.standardError.write(Data(text.utf8)) }
        }
        p.terminationHandler = { proc in
            Task { @MainActor in
                EngineHelper.shared.pageURL = nil
                EngineHelper.shared.status = "The engine stopped (exit \(proc.terminationStatus))."
                EngineHelper.shared.process = nil
            }
        }
        do {
            try p.run()
        } catch {
            status = "The engine did not start: \(error.localizedDescription)"
            return
        }
        process = p
        status = "Starting the engine on 127.0.0.1:\(port)…"
        let url = URL(string: "http://127.0.0.1:\(port)/")!
        Task { await waitFor(url) }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    /// Waits until the engine answers, then shows the page.
    private func waitFor(_ url: URL) async {
        for _ in 0..<150 {
            if process == nil { return }
            if let (_, res) = try? await URLSession.shared.data(from: url), (res as? HTTPURLResponse)?.statusCode == 200 {
                pageURL = url
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        status = "The engine did not answer on \(url.absoluteString)."
    }

    /// A port the system has free now: bind to port 0 and read what it gave.
    static func freePort() -> UInt16? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0
        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        let bound = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, len) == 0 && getsockname(fd, $0, &len) == 0 }
        }
        return bound ? UInt16(bigEndian: addr.sin_port) : nil
    }
}
