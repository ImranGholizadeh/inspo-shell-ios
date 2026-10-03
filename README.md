<!-- Copyright (c) 2026 Imran Gholizadeh, doing business as Inspo. All rights reserved.
     Proprietary and confidential. -->
# The Inspo shell for iOS

The native iOS mine: one web view on a gene's page, served by the Go engine
(audit-runner) and drawn by the thin renderer (inspo-core-js), plus what only a
phone has. Mobile is a mine of its own, separate from the web mine (owner,
2026-09-26); Swift was chosen for it as the low-hanging fruit (2026-09-29).

## What the shell adds

| The page asks or hears | The shell |
|---|---|
| what this shell does | `window.inspoShell.acts`, a list of words set before the page's own script runs (`Shell/ShellActs.swift`): `haptic`, `vibrate`, `torch`, `share`, `clipboard`, `native` here; `haptic`, `native` in the desktop app. A page and a shell are not built together, so the page never hands the shell a request whose word is not there: it does it the web view's own way or says at once that it cannot, and a shell that says nothing (one built before this) is taken to do what the oldest did: `haptic`, `torch`, `native`. `scripts/check-acts.sh` holds each word to a case of its bridge |
| a haptic (the device neuron's `haptic`) | `window.webkit.messageHandlers.inspo.postMessage({type: "haptic", mode})`, played by iOS's feedback generators. The mode `vibrate` is the system's own long vibration (about 0.4 s of the phone's motor, as a message's; it plays on silent too, unless the person switched vibration off): felt in a pocket, where a feedback generator's tap is not. A device with no motor plays nothing |
| a share (the device neuron's `share`) | `{type: "share", id, text, url}` (a text, a link or both) or `{type: "share", id, file: {name, mime, text}}`: iOS's share sheet opens over the page (`Shell/HandOver.swift`, `Shell/PhoneHandOver.swift`). A file's `text` is written under its `name` in the app's temporary folder, shared as a file, and removed when the sheet closes. Answered once: `window.inspo.deviceAnswered(id)` when the sheet has closed, whether the person shared or put it away, or `deviceFailed(id, reason)` when it could not be opened. A file's name with a folder in it, a link that is not http or https, a text or a file of more than 1,000,000 bytes and a sheet already open are refused with the reason. `scripts/check-share.sh` checks it on this Mac, with no phone |
| the clipboard (the device neuron's `clipboard`) | `{type: "clipboard", id, text}`: the text is put on the phone's clipboard, and `window.inspo.deviceAnswered(id)` says so |
| the light (the device neuron's `torch`) | `{type: "torch", mode: "on"}` or `{type: "torch", mode: "off"}`, switched on the phone's own light (`Shell/Torch.swift`); never answered. A device with no light switches nothing. A light the shell lit goes out when its page goes (a reload, a page that ended) and when the app leaves the screen. `scripts/check-torch.sh` checks it on this Mac, with no phone |
| the camera (the device neuron's `camera`) | grants the web view's camera to the gene's own site only; iOS asks the person once |
| `link-opened` | a link to the app's URL scheme calls `window.inspo.linkOpened(url)` |
| a native library's call or event stream (a db neuron of type exotic on a `native://<library>/<name>` endpoint) | `{type: "native", id, url, data, keep, listen}` or `{type: "native", id, stop: true}`; the library's adapter (a `NativeLibrary`, registered with `NativeLibraries.shared`) answers, and the shell keeps only the fields `keep` names before calling `window.inspo.nativeAnswered(id, value)` or `nativeFailed(id, error)` |

Calls made before the page is ready wait in `window.inspoWaiting`; the page's
`app.js` takes them in order.

A page that does not load (the app opened with no signal, or brought back by
iOS with none) is loaded again by itself: after a wait that doubles from one
second to fifteen, and at once when iOS says the network is back or the app
comes to the front (`Shell/LoadAgain.swift`; `scripts/check-load.sh` checks its
timing on this Mac). Until a page has loaded the app shows its splash, as the
launch screen draws it, not an empty view; while iOS says there is no network,
a small sign near the bottom edge says so, in no language.

## Building

Nothing of a customer is in this repository. `Config/Default.xcconfig` points
at Inspo's own tally test (https://client-inspo.web.app/tally). A customer's
lane builds with its own xcconfig, which sets `INSPO_URL` (written
`https:/$()/...`, since `//` starts a comment), `INSPO_APP_NAME`,
`INSPO_BUNDLE_ID` and `INSPO_URL_SCHEME`:

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
      -project Shell.xcodeproj -scheme Shell -sdk iphonesimulator \
      -destination 'platform=iOS Simulator,name=iPhone 17' \
      -xcconfig <lane>/deploy/ios.xcconfig build

A test build may set `INSPO_NATIVE_STAND_IN` to a library's name (`id-reader`):
`StandInReader` then stands in for the Bluetooth ID scanner, with made-up
events played one per press of either volume button, so a gene's scan flow
runs with no device. A first pairing plays too: the press that comes while it
waits for the confirming scan is that scan. A scanner that is away plays by a
link to the app, `<the app's url scheme>://stand-in/<scene>`, which the
stand-in takes for itself (on a simulator: `xcrun simctl openurl booted
<scheme>://stand-in/away`; on a phone, the link tapped in Notes or Safari):

| Scene | What it plays |
|---|---|
| `away` | the paired scanner goes out of range: the link drops and the phone waits for it. As the link that opens the app, a phone opened with its scanner away: paired, idle, nothing asked yet |
| `bluetooth-off` | Bluetooth is switched off: a connected scanner drops, and nothing can be connected |
| `bluetooth-refused` | Bluetooth is not allowed for this app |
| `back` | Bluetooth is on and allowed again and the scanner is near: a scanner that is waited for connects in under a second |
| `keyboard-mode` | the scanner is set to type as a keyboard: the warning, the link drops, and a connection meets the warning again until `back` |
| `low-battery` | the battery at 8 percent, and the warning |
| `unpaired` | no scanner is paired with this phone (a first pairing pairs the stand-in again) |
| `paired` | the stand-in as it starts: paired and connected |

### A customer's brand: its icon and its splash

The shell's own icon is a placeholder and its splash is plain (the system's
background, no mark). A customer's icon and splash stay in the customer's
lane and are laid over the shell's at build time (owner, 2026-10-03:
"Overlay at build time"):

1. The lane keeps a folder of asset sets, as Xcode writes them:
   `AppIcon.appiconset` (one 1024 by 1024 image, no transparency), and for
   the splash `LaunchBackground.colorset` (its colour) and
   `LaunchMark.imageset` (the mark drawn in its middle). The icon is needed;
   a set left out stays the shell's.
2. Its xcconfig names the folder: `INSPO_BRAND_ASSETS = <the folder>` (from
   the root, or from the xcconfig's own place).
3. A lane that keeps its own copy of `Shell/Info.plist` (the scanner build
   below) carries the shell's `UILaunchScreen` in it, which names the two
   splash sets:

       <key>UILaunchScreen</key>
       <dict>
           <key>UIColorName</key>
           <string>LaunchBackground</string>
           <key>UIImageName</key>
           <string>LaunchMark</string>
       </dict>

The key is read by the build scripts, not by Xcode: `scripts/archive.sh` and
`scripts/simulator.sh` (through `scripts/brand-overlay.sh`) copy the shell to
a temporary folder, lay the lane's sets over `Shell/Assets.xcassets` there,
build from the copy, and remove it when the script ends, however it ends.
The copy's project names this repository's `Packages/` where they are, so a
lane's workspace and binding build as before. Nothing of the brand is ever
written into this repository, and a build with plain `xcodebuild` or from
Xcode carries the shell's placeholder. A folder with no `AppIcon.appiconset`,
a set that could not be copied, or a workspace that does not hold
`Shell.xcodeproj` stops the build with the reason. `scripts/check-brand.sh`
checks all of it on this Mac, with a made-up lane and an xcodebuild that only
records what it was asked to build.

To try a lane's app on the simulator, its icon and splash included:

    scripts/simulator.sh <lane xcconfig> [<lane workspace>]

It builds a development build, unsigned, into `build/simulator` (or
`INSPO_BUILD_DIR`), and prints the app's path and the two `xcrun simctl`
commands that install and launch it on the booted simulator.

To upload a lane's build: `scripts/archive.sh <lane xcconfig>`, then
`scripts/upload.sh` (the newest lane archive, or one named), which sends it
to App Store Connect with its team's signing, no Organizer needed. An archive
made from Xcode's Product > Archive carries the shell's defaults, not a lane's.

For a phone, open `Shell.xcodeproj` in Xcode, choose the team, and run; for
TestFlight, Product > Archive, then Distribute to App Store Connect.

## The Bluetooth ID scanner (E47)

`Shell/IDScanner.swift` is the adapter that maps a vendor's Bluetooth ID
scanner package onto a gene's endpoint documents. It is written against
`BluetoothIDScanner`, the scanner's surface in plain terms, in its own
module (`Packages/IDScannerSurface`). The vendor's package is never in this
repository; the shell links `Packages/IDScannerBinding`, which links no
scanner. The stand-in conforms to the same surface, so its answers take
the same shape.

| Endpoint (`native://<library>/<name>`) | What the adapter does |
|---|---|
| `state` (call) | at once, never waiting for a connection: `{kind: "state", state, battery, paired, reason}`. `battery` is the percent, once the scanner has said it; `paired` is 1 when a scanner is paired with this phone and 0 when none is (a number); `reason` is why a scanner is not connected (below) |
| `feedback` (call, data `accept`, `deny` or `error`, or `{pattern}`) | accept plays the package's success feedback; deny and error its error feedback |
| `start-reading`, `stop-reading` (calls) | subscribe and unsubscribe the package's result listener |
| `reconnect` (call, data none or `{wait: 0}`) | connects the paired scanner again. With no data it answers `{}` when the scanner is connected, however long that takes, as it always has (the gene gives the call its time limit). With `{wait: 0}` it answers at once with the state it moved to, in the `state` call's shape, and the connection comes on the stream. No scanner paired: the call fails, either way |
| `forget` (call) | forgets the paired scanner the package's status names |
| `start-pairing` (call, data `{venue, door, doorName}`, each optional) | starts pairing a scanner this phone has never used, and answers at once with `{kind: "pairing", step}`: `looking`, or the step of the pairing that already runs, which goes on. The data is where the scanner is paired; the package keeps it with the pairing, on the phone, beside iOS's id of the phone for the app's maker, which the shell adds |
| `stop-pairing` (call) | stops the pairing that runs |
| `events` (stream) | every event flat, with a kind: `read`, `failedRead` or `failedValidation` (with `fullName`, `dateOfBirth`, `expirationDate`, `isOver21`, `isExpired` when read, and `issueCode`, the first issue); `duplicate` (with `result`, the suppressed result's kind only); `state` (`state`, and `reason` when the scanner is not connected: a real connection change, at once; the package's `reading` during each scan is held back and reads as `connected`); `battery` (`battery`, the percent); `warning` (`warning`: `keyboard-mode` or `low-battery`); `pairing` (`step`: `looking`, `connecting`, `confirm`, `paired` or `failed`, and with `failed` a `reason`) |

The adapter configures the package once, on first use: its age and expiry
checks on, its duplicate window as delivered, reporting off the phone never
configured. Nothing but the fields above leaves the adapter, and the shell
keeps only those the endpoint's `keep` names.

### A paired scanner that is not connected: paired, the reason, at once

A gene's scanner pill must say within a second whether this phone has a
scanner and whether it is there (the first customer's request Q011), so:

- **`paired`** comes with every `state` answer, from the package's own list of
  paired scanners, read at the call.
- **The state while a paired scanner is away is `reconnecting`.** The phone
  waits for a paired scanner with no time limit and connects it when it is
  heard again; the package's state while it waits is `connecting`, the same
  as while a first pairing connects its pick. Outside a pairing the adapter
  tells a paired scanner's `connecting` as `reconnecting`, so `connecting` is
  only a first pairing's connection being made. A phone just opened, with a
  scanner paired and nothing asked yet, is `idle` with `paired` 1.
- **`reason`** comes with `disconnected` and `reconnecting`, and with `idle`
  when a scanner is paired:

  | `reason` | When |
  |---|---|
  | `bluetooth-off` | Bluetooth is switched off, as iOS says it now |
  | `bluetooth-not-allowed` | Bluetooth is not allowed for this app, by the person or the phone's rules |
  | `out-of-range` | the package said the link dropped or timed out, and the scanner has not connected since. A scanner switched off reads the same: the package cannot tell them apart |
  | `switched-off` | kept for a package that can tell it; none does, so it is never sent today |
  | `unknown` | anything else: nothing asked yet, a scanner asked for that has not answered, a scanner forgotten, a scanner in keyboard mode (the warning says so) |

- **A `state` event comes at once** when the link drops, when Bluetooth goes
  off or is refused, when it comes back, and when the scanner is connected
  again; also when only the reason has changed (Bluetooth switched off while
  the scanner was already away), so the same `state` may come twice with
  another `reason`.
- **Bluetooth coming back on** makes the adapter ask for the paired scanner
  again: Bluetooth going off ends the phone's wait without a word, and the
  scanner would otherwise never connect until someone tapped Reconnect.
- **`reconnect` with `{wait: 0}`** answers at once (`reconnecting` for a
  scanner now waited for, `connected` for one that is, the state as it is
  with its `reason` when Bluetooth is off or not allowed, and then the
  scanner is asked for when Bluetooth is back). A gene built before this
  sends no data and gets the answer it always got.

Bluetooth's own state is the binding's to read (`BluetoothWatch` in
`Bindings/VendorIDScanner.swift`: a central of its own that connects nothing),
since a scanner's package says when Bluetooth goes off and nothing when it
comes back. `scripts/check-reader.sh` checks all of it on this Mac, with a
scanner that only records what it was asked, and plays the stand-in's scenes.

### A first pairing: the nearest scanner, confirmed by a scan

The person is shown no list (owner, 2026-10-02: "Nearest scanner, confirm by
scan"). `start-pairing` answers at once, since a call must answer within 30
seconds and a pairing takes up to a minute; its steps come on the `events`
stream, each `{kind: "pairing", step}`:

| Step | What has happened | Its time limit, and the reason when it fails |
|---|---|---|
| `looking` | the package looks for scanners | 15 s with none heard: `none-found` |
| `connecting` | 3 s after the first scanner was heard, the adapter picked the one with the strongest signal (the first heard of two equally strong) and connects it | 10 s: `not-connected` |
| `confirm` | the pick is connected; the person scans any barcode with the scanner in their hand, which the package reads and discards | 30 s: `not-confirmed` |
| `paired` | the package has kept the pairing; the scanner is connected, as after `reconnect` | |
| `failed`, with `reason` | one of the three above, or `stopped` (`stop-pairing`), `bluetooth-off`, `bluetooth-not-allowed`; or `already-connected`, at once and with nothing started, when a scanner is connected (forget it first to pair another) | |

The scan is the guard: a pick that is not the scanner in the person's hand is
never confirmed, fails as `not-confirmed`, and is forgotten, so the phone is
not left connected to it (a scanner that was paired before the pairing began
is not forgotten). The scanners heard are never passed on. Nothing of a
pairing is personal, and nothing of the confirming scan leaves the package. A
stream opened while a pairing runs hears its step after its first state.
`scripts/check-pairing.sh` checks all of it on this Mac, with a scanner that
only records what it was asked and a clock the check moves, and plays the
stand-in's pairing.

### A customer build: its own Xcode workspace

The customer's lane, never this repository, holds:

1. `<lane>/ios/Customer.xcworkspace`, holding this repository's
   `Shell.xcodeproj` and the folder `IDScannerBinding` beside it. Xcode
   builds the workspace's `IDScannerBinding` package in place of the
   shell's own (the same package name), so the shell links the binding.
2. `<lane>/ios/IDScannerBinding/`, a Swift package named `IDScannerBinding`
   with one library product of that name, whose one source is
   `Bindings/VendorIDScanner.swift` from this repository with the vendor
   module's import line added (copied again whenever that file changes
   here: the binding and the surface are built together), and which depends
   on this repository's
   `Packages/IDScannerSurface` (by path) and on the vendor's package (by
   path, where the customer keeps it):

       // swift-tools-version:5.9
       import PackageDescription
       let package = Package(
           name: "IDScannerBinding",
           platforms: [.iOS(.v17), .macOS(.v14)],
           products: [.library(name: "IDScannerBinding", targets: ["IDScannerBinding"])],
           dependencies: [.package(path: "<shell>/Packages/IDScannerSurface"),
                          .package(path: "<the vendor's package>")],
           targets: [.target(name: "IDScannerBinding",
                             dependencies: ["IDScannerSurface",
                                            .product(name: "<its library>", package: "<its package>")])]
       )

3. Its xcconfig, beside `INSPO_URL` and the rest: `INSPO_ID_SCANNER =
   id-reader` (the library's name in its urls), and the two Bluetooth keys
   the app's Info.plist must carry for the scanner:
   - `NSBluetoothAlwaysUsageDescription`, the reason iOS shows when it asks
     for Bluetooth: `INFOPLIST_KEY_NSBluetoothAlwaysUsageDescription = ...`
     in the xcconfig;
   - `UIBackgroundModes` with `bluetooth-central`, so the scanner stays
     connected while the phone is locked. Xcode builds no setting for it,
     so the lane keeps its own copy of `Shell/Info.plist` with the key
     added, and its xcconfig sets `INFOPLIST_FILE` to that copy.

Then: `xcodebuild -workspace <lane>/ios/Customer.xcworkspace -scheme Shell
-xcconfig <lane>/deploy/ios.xcconfig ...`, as for any lane build;
`scripts/simulator.sh <lane xcconfig> <lane workspace>` to try it on the
simulator and `scripts/archive.sh <lane xcconfig> <lane workspace>` to
archive it, both with the lane's brand when its xcconfig names one. A build
without the workspace (this repository alone, or a test build with the
stand-in) links no scanner and declares no Bluetooth.

## The Inspo desktop app (the Desktop target)

The desktop app (owner, 2026-09-30: the top priority outside client work;
"macOS target in inspo-shell-ios", "The audit binary as a helper"): a window
with one web view, and the Go engine inside the app. Its build phase
(`scripts/bundle-engine.sh`) builds `audit` from audit-runner for this Mac
and copies the built renderer from inspo-core-js into
`Inspo.app/Contents/Resources/engine`, with the pages in
`Config/desktop-pages/`. At launch the app starts `audit mine-serve` on a
free loopback port, serving that page to its own web view; the engine reads
`INSPO_DESKTOP_READ` in `INSPO_DESKTOP_PROJECT` with the person's own gcloud
sign-in, and stops when the app quits. It opens the p viewer first
(`Config/Desktop.xcconfig`). `NativeLibrary.swift` is shared with the iOS
shell; a haptic plays on the trackpad, and a torch switches nothing (a Mac
has no light).

    DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild \
      -project Shell.xcodeproj -scheme Desktop -configuration Debug build
