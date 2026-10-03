// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import SwiftUI

// The Inspo shell: the native iOS mine (owner, 2026-09-26: mobile is a
// separate mine, React Native or Swift; 2026-09-29: "if swift is low
// hanging fruit go for it"). It holds one web view on the gene's page; the
// Go engine runs the graph and the page draws it, as on the web. The shell
// adds only what a phone has and a page does not: haptics and the long
// vibration, the camera, the light, the share sheet and the clipboard, the
// links that open the app, and native libraries (a vendor's reader).
@main
struct ShellApp: App {
    @ObservedObject private var state = ShellBridge.shared.state
    var body: some Scene {
        WindowGroup {
            ZStack {
                ShellView()
                    .ignoresSafeArea()
                // the splash stays until a page has loaded (ShellBridge.swift)
                if !state.pageLoaded {
                    SplashView(state: state)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: state.pageLoaded)
            .onOpenURL { ShellBridge.shared.linkOpened($0) }
        }
    }
}
