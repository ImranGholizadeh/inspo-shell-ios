// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import SwiftUI

// The Inspo desktop app (owner, 2026-09-29: "I want it to be a desktop
// app"; 2026-09-30: the top priority outside client work, "macOS target in
// inspo-shell-ios", "The audit binary as a helper"). A window with one web
// view; the Go engine runs inside the app, as the same audit binary the
// servers run, started as a helper on a loopback port only this app knows,
// and the page draws what it streams. It opens the p viewer first.
// Since 13 October 2026 (owner: "I want to use it from an x code build") it
// opens the workspace instead where Config/Desktop.xcconfig says so
// (INSPO_DESKTOP_OPENS = workspace): the editor's several engines, started
// and stopped by the standing scripts (WorkspaceHelper.swift). Since 20
// October 2026 (the owner's shape C, a staging place of Inspo's own) it may
// open the editor's page at an address instead (INSPO_DESKTOP_OPENS =
// address, INSPO_DESKTOP_ADDRESS), starting and stopping nothing. What it
// did before is any other word there.
@main
struct DesktopApp: App {
    @NSApplicationDelegateAdaptor(DesktopDelegate.self) var delegate
    @StateObject private var engine = EngineHelper.shared
    @StateObject private var workspace = WorkspaceHelper.shared
    static let opens = Opens(DesktopWords.word)
    /// The editor's page, the workspace's or one at an address (Opens).
    static let opensWorkspace = opens.editorsPage
    /// The window's first size, as the config says it (two numbers); the
    /// system keeps the size a person then gives it.
    static let firstSize: CGSize = {
        let said = DesktopWords.word("InspoWindow").split(separator: " ").compactMap { Double($0) }
        return said.count == 2 && said[0] >= 960 && said[1] >= 600 ? CGSize(width: said[0], height: said[1]) : CGSize(width: 960, height: 632)
    }()

    var body: some Scene {
        WindowGroup {
            Group {
                if let url = Self.opensWorkspace ? workspace.pageURL : engine.pageURL {
                    // the page runs under the title bar, as Finder's and
                    // Music's do (owner, 2026-09-30: "Page runs under it");
                    // the traffic lights float over it, and the page is told
                    // the bar's height as its safe area (DesktopBridge)
                    // (under it, the words a person reads while the page
                    // is kept from sight: INSPO_DESKTOP_SHOWN_AGAIN)
                    ZStack {
                        if Self.opensWorkspace { EngineStatusView(status: "") } // (the ground alone: no words before the opening)
                        DesktopView(url: url).ignoresSafeArea()
                    }
                } else if Self.opensWorkspace {
                    EngineStatusView(status: workspace.status,
                                     offer: workspace.offersToStop ? "Stop it and open the editor here" : nil) { workspace.stopItAndOpen() }
                } else {
                    EngineStatusView(status: engine.status)
                }
            }
            .frame(minWidth: 960, minHeight: 600)
            .task {
                if Self.opensWorkspace { workspace.open(); FirstFrame.began() } else { engine.start() }
                #if DEBUG
                Rehearsal.shared.begin()
                #endif
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(Self.firstSize)
        .commands {
            CommandGroup(after: .appInfo) {
                Button("Show This Launch's Logs") { workspace.showLogs() }
                    .disabled(!Self.opensWorkspace)
            }
            CommandGroup(after: .toolbar) {
                // a page that was not drawn again for a new size is loaded again by hand
                Button("Reload Page") { DesktopBridge.shared.webView?.reload() }
                    .keyboardShortcut("r")
            }
        }
    }
}

final class DesktopDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        EngineHelper.shared.stop() // the engine never outlives the app
        WorkspaceHelper.shared.quit() // nor the workspace this launch started: the stop's own words
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// What the window shows while the engine starts, or why it could not, in
/// words; and one thing to press where the words offer it.
struct EngineStatusView: View {
    let status: String
    var offer: String?
    var pressed: () -> Void = {}
    var body: some View {
        ZStack {
            Color(hue: 214 / 360, saturation: 0.33, brightness: 0.12)
            VStack(spacing: 20) {
                Text(status)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Color(hue: 214 / 360, saturation: 0.33, brightness: 0.8))
                    .textSelection(.enabled)
                if let offer {
                    Button(offer, action: pressed)
                }
            }
            .padding(24)
        }
        .ignoresSafeArea()
    }
}
