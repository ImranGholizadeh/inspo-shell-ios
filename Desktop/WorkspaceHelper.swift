// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import AppKit
import Foundation

// The desktop app opening the workspace (Workspace.swift): at launch it
// makes the launch's folder of logs, looks at what stands, runs the start
// and shows the page when it answers; at quit it runs the stop. What the
// window says while it waits, and when a start fails, is words: the start's
// own last lines.
@MainActor
final class WorkspaceHelper: ObservableObject {
    static let shared = WorkspaceHelper()

    @Published private(set) var pageURL: URL?
    @Published private(set) var status = "Opening the workspace…"
    /// A workspace is up that this app did not start: the window offers to stop it.
    @Published private(set) var offersToStop = false

    private(set) var folder = ""
    private(set) var app: LogFile?
    private(set) var page: LogFile?
    private var run: WorkspaceRun?
    private var began = false

    func open() {
        guard !began else { return }
        began = true
        let words = WorkspaceWords(DesktopWords.word)
        guard let folder = LaunchLogs.begin(root: words.logs) else {
            status = "This launch's folder of logs could not be made in: \(words.logs.isEmpty ? "(INSPO_DESKTOP_LOGS says none)" : words.logs)"
            return
        }
        self.folder = folder
        app = LogFile(folder + "/app.log")
        page = LogFile(folder + "/page.log")
        say("launch: \(Bundle.main.bundlePath), pid \(ProcessInfo.processInfo.processIdentifier)")
        say("the workspace: start \(words.start), stop \(words.stop), port \(words.port)")
        if let fault = words.fault {
            show(fault)
            return
        }
        let run = WorkspaceRun(words, folder: folder)
        self.run = run
        switch run.standing() {
        case .none:
            start()
        case .ofAnEarlierLaunch(let pid):
            say("a workspace of an earlier launch that did not quit is up (pid \(pid), launch \(run.earlierLaunch)): stopping it by the stop")
            status = "An earlier launch did not quit: stopping its workspace, then opening it again…"
            stopWhatStood(then: true)
        case .ofAnotherStart(let pid):
            say("a workspace is up that this app did not start (pid \(pid)): nothing is stopped")
            status = "A workspace is already open on this Mac (pid \(pid)), and this app did not start it.\nOne workspace runs at a time. Stop it where you started it, then open this app again,\nor have it stopped here by its own stop."
            offersToStop = true
        }
    }

    /// The person's word, in the window: the stop is run on what stands, then the start.
    func stopItAndOpen() {
        guard offersToStop else { return }
        offersToStop = false
        say("the person asked for the stop of the workspace that was up")
        status = "Stopping the workspace that was open, then opening it again…"
        stopWhatStood(then: true)
    }

    private func stopWhatStood(then start: Bool) {
        guard let run else { return }
        Task.detached {
            let code = run.stopWhatStood()
            let alive = run.livePid()
            await MainActor.run {
                self.say("the stop of what stood ended with \(code)\(alive.map { ", and pid \($0) still lives" } ?? "")")
                if alive != nil {
                    self.show("The workspace that was open did not stop. The stop's last lines:\n\n" + run.lastLines(of: "stop-of-what-stood.log"))
                } else if start {
                    self.start()
                }
            }
        }
    }

    private func start() {
        guard let run else { return }
        status = "Starting the workspace (its engines take a few seconds)…"
        say("the start begins")
        Task.detached {
            let code = run.start()
            await MainActor.run {
                self.say("the start ended with \(code)")
                if code == 0, let url = URL(string: run.words.address) {
                    self.pageURL = url
                } else {
                    self.show("The workspace did not start (the start ended with \(code)). Its last lines:\n\n" + run.lastLines(of: "start.log"))
                }
            }
        }
    }

    /// At quit: the workspace this launch started is stopped by the stop's
    /// own words. One this launch did not start is left as it is.
    func quit() {
        guard let run else { return }
        say("quit")
        if let code = run.quit() {
            say("quit: the stop ended with \(code)")
        } else {
            say("quit: this launch started no workspace, so nothing is stopped")
        }
        app?.settle()
        page?.settle()
    }

    /// The Finder shows this launch's folder (the menu's item).
    func showLogs() {
        guard !folder.isEmpty else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder)
    }

    func say(_ line: String) { app?.line(line) }

    private func show(_ words: String) {
        pageURL = nil
        status = words
        say("the window says: \(words)")
    }
}
