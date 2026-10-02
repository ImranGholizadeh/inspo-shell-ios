// Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
// Proprietary and confidential.

import SwiftUI

// The Inspo shell: the native iOS mine (owner, 2026-09-26: mobile is a
// separate mine, React Native or Swift; 2026-09-29: "if swift is low
// hanging fruit go for it"). It holds one web view on the gene's page; the
// Go engine runs the graph and the page draws it, as on the web. The shell
// adds only what a phone has and a page does not: haptics, the camera, the
// light, the links that open the app, and native libraries (a vendor's
// reader).
@main
struct ShellApp: App {
    var body: some Scene {
        WindowGroup {
            ShellView()
                .ignoresSafeArea()
                .onOpenURL { ShellBridge.shared.linkOpened($0) }
        }
    }
}
