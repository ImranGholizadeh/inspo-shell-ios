// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import SwiftUI

// The Inspo desktop app (owner, 2026-09-29: "I want it to be a desktop
// app"; 2026-09-30: the top priority outside client work, "macOS target in
// inspo-shell-ios", "The audit binary as a helper"). A window with one web
// view; the Go engine runs inside the app, as the same audit binary the
// servers run, started as a helper on a loopback port only this app knows,
// and the page draws what it streams. It opens the p viewer first.
@main
struct DesktopApp: App {
    @NSApplicationDelegateAdaptor(DesktopDelegate.self) var delegate
    @StateObject private var engine = EngineHelper.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if let url = engine.pageURL {
                    // the page runs under the title bar, as Finder's and
                    // Music's do (owner, 2026-09-30: "Page runs under it");
                    // the traffic lights float over it, and the page is told
                    // the bar's height as its safe area (DesktopBridge)
                    DesktopView(url: url).ignoresSafeArea()
                } else {
                    EngineStatusView(status: engine.status)
                }
            }
            .frame(minWidth: 960, minHeight: 600)
            .task { engine.start() }
        }
        .windowStyle(.hiddenTitleBar)
    }
}

final class DesktopDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        EngineHelper.shared.stop() // the engine never outlives the app
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// What the window shows while the engine starts, or why it could not.
struct EngineStatusView: View {
    let status: String
    var body: some View {
        ZStack {
            Color(hue: 214 / 360, saturation: 0.33, brightness: 0.12)
            Text(status)
                .font(.system(size: 13, design: .monospaced))
                .foregroundStyle(Color(hue: 214 / 360, saturation: 0.33, brightness: 0.8))
                .padding(24)
        }
        .ignoresSafeArea()
    }
}
