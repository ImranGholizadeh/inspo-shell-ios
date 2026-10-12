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
| a share (the device neuron's `share`) | `{type: "share", id, text, url}` (a text, a link or both) or `{type: "share", id, file: {name, mime, text}}`: iOS's share sheet opens over the page (`Shell/HandOver.swift`, `Shell/PhoneHandOver.swift`). A file's `text` is written under its `name` in the app's temporary folder, shared as a file, and removed when the sheet closes. Answered once: `window.inspo.deviceAnswered(id)` when the sheet has closed, whether the person shared or put it away, or `deviceFailed(id, reason)` when it could not be opened. A file's name with a folder in it or a character that is not shown, a file whose type is not one a share's file may have (`text/csv`, `text/tab-separated-values`, `text/plain`, `text/markdown`, `application/json`) or whose name does not end as its type does, a link that is not an https address, carries a user or a password or is longer than 2,048 bytes, a text or a file of more than 1,000,000 bytes and a sheet already open are refused with the reason. One sheet is open at a time, and nothing holds that for ever: a sheet that could not be opened says so, at once or when it is still not up five seconds after it was asked (iOS puts a share sheet up a moment after it is asked, a third of a second on iOS 26, so a sheet on its way is waited for and its file kept, and one that comes after it was given up is taken down again); one iOS took down without a word is found gone when the next share asks; a request that arrives twice opens one sheet and is answered once; a share asked as the sheet before it closes opens when that has gone. A page that loads afresh under an open sheet leaves the sheet to the person: its file goes when it closes, and no page is answered. A file an app that ended with its sheet open left is removed when the app opens. `scripts/check-share.sh` checks it on this Mac, with no phone |
| the clipboard (the device neuron's `clipboard`) | `{type: "clipboard", id, text}`: the text is put on the phone's clipboard, and `window.inspo.deviceAnswered(id)` says so. With `forSeconds` (a whole number from 1 to 3,600: a PIN, a one-time code) the clipboard holds the text for that long and then lets it go, and keeps it to this phone, never passed to the person's other devices; without it a copy is iOS's usual one |
| the light (the device neuron's `torch`) | `{type: "torch", mode: "on"}` or `{type: "torch", mode: "off"}`, switched on the phone's own light (`Shell/Torch.swift`); never answered. A device with no light switches nothing. A light the shell lit goes out when its page goes (a reload, a page that ended) and when the app leaves the screen. `scripts/check-torch.sh` checks it on this Mac, with no phone |
| the camera (the device neuron's `camera`) | grants the web view's camera to the gene's own site only; iOS asks the person once |
| `link-opened` | a link to the app's URL scheme calls `window.inspo.linkOpened(url)` |
| push: the person's leave, the phone's push token, a notification's tap (`native://push/permission`, `native://push/token`, `native://push/events`) | a native library of the shell's own (`Shell/Push.swift`, below): each done when a record's call asks, never at launch or by itself |
| a native library's call or event stream (a db neuron of type exotic on a `native://<library>/<name>` endpoint) | `{type: "native", id, url, data, keep, listen}` or `{type: "native", id, stop: true}`; the library's adapter (a `NativeLibrary`, registered with `NativeLibraries.shared`) answers, and the shell keeps only the fields `keep` names before calling `window.inspo.nativeAnswered(id, value)` or `nativeFailed(id, error)` |

Calls made before the page is ready wait in `window.inspoWaiting`; the page's
`app.js` takes them in order.

**The shell answers the build's own page and no other** (`Shell/OwnPage.swift`).
A web view goes where a link takes it, and the bridge is in every page it
holds, so a link out of a gene's site would put another site's page in the
app with the bridge in it; and what a page is handed is what its own
request's `keep` names, which protects a read only while the page is the
gene's. So a request is taken only from the main frame of a page whose
origin is the origin of the build's page (`INSPO_URL`: its scheme, host and
port). A page of any other origin, and a frame inside any page, is answered
nothing: no call, no stream, no haptic, light, share or clipboard, and no
word that it was refused. What the shell tells a page (an answer, a stream's
event, a link that opened the app) is told only while the page the web view
holds is the build's own, and an answer only to the page that asked: when
another page takes its place, what waited for the page before is nobody's.
The page told is the one whose first bytes last came in, never the web
view's own address: that is the address of a load in flight as soon as one
starts, and a page of another origin with a load of the build's own page
in flight would else be told the link that opened the app.
The shell does not keep such a page out of the web view (a sign-in that
passes through another site and comes back is one); it answers it nothing.
`scripts/check-door.sh` holds it on this Mac.

A page that does not load (the app opened with no signal, or brought back by
iOS with none) is loaded again by itself: after a wait that doubles from one
second to fifteen, and at once when iOS says the network is back or the app
comes to the front (`Shell/LoadAgain.swift`; `scripts/check-load.sh` checks its
timing on this Mac). Until a page has loaded the app shows its splash, as the
launch screen draws it, not an empty view; while iOS says there is no network,
a small sign near the bottom edge says so, in no language.

### The edges the hardware covers, and when a page is told of them

A page reads the edges of the screen the hardware covers (the status bar
and its island, the home bar) from the web view itself
(`env(safe-area-inset-top)` and the three others), and the engine offers
them to a gene as the safe-area tokens. The shell lays the web view over the
whole screen.

A page that has just started reads 0 for every edge: the web view tells a
new page's content its covered edges only after the page's first drawing,
about a twentieth of a second after its script began, and makes no event
of it (the window's size has not changed). Measured on a simulator, 20
starts of 20: 0 as the page started, the true 62 between 46 and 82 ms
later, no resize event. Loading the page later does not change it (held
until the web view was in its window and knew its covered top: 0 still,
three starts of three), nor does loading an empty page of the same site
first (five of five).

So the shell makes the event the web view leaves out
(`Shell/CoveredEdges.swift`): a script added to every page keeps one hidden
mark padded by the web view's own four edges, and when the mark's size
changes it tells the window a `resize`, the event a page already takes to
read its screen again. The shell says no number by it: the page reads the
edges itself.

That tells a page; it does not move what a page has already drawn. A page
told a moment after its first drawing tells its engine the true screen, and
today's engine draws nothing again for a screen whose size is the same and
whose covered edges differ: on the real page, served from this Mac, 16
starts of 20 stayed under the status bar with the event alone. So the shell
also says the web view's own covered edges to a page as the page starts,
through the hook a page already reads for an edge its browser does not know
of: `window.inspoSafeArea = {top, right, bottom, left}`, of which the page
takes the larger of the hook's word and the browser's for each edge. The
numbers are the web view's own safe area, in points (a page's px): the same
its browser tells the page a twentieth of a second later, and no other. The
shell says them again, with a `resize`, whenever they change, so the hook
holds no edge the web view no longer has; and the first page is loaded when
the web view is first laid out in its window, when the edges are known (a
web view laid out in no window loads its page a second on, all the same).
With both, 20 starts of 20 on the real page are drawn under the status bar's
edge and not under the bar. And since the page has then read the edges as
it started, the web view's own first word of those same edges, a moment
later, is told by no resize: a page holds its transitions for a while at a
resize, and would at every start. Every other change of the edges is told. `scripts/check-edges.sh` runs both scripts in a
JavaScript engine against a document that only records.

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
| `keyboard-mode` | the scanner is set to type as a keyboard: the warning, the link drops, and a connection asked of it is refused with the warning again until `back` (the adapter holds that: the page hears the warning once) |
| `low-battery` | the battery at 8 percent, and the warning |
| `unpaired` | no scanner is paired with this phone (a first pairing pairs the stand-in again); the stream's state event says `paired` 0 at once, whatever the state was |
| `paired` | the stand-in as it starts: paired and connected |
| `press` | a press of a volume button, for a simulator, which has none: the script's next event, or the confirming scan of a pairing that waits for it |

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
| `start-reading`, `stop-reading` (calls) | subscribe and unsubscribe the package's result listener; while reading is stopped a scan reaches an open stream as `unread`, with no field of it |
| `reconnect` (call, data none or `{wait: 0}`) | connects the paired scanner again. With no data it answers `{}` when the scanner is connected, however long that takes, as it always has (the gene gives the call its time limit). With `{wait: 0}` it answers at once with the state it moved to, in the `state` call's shape, and the connection comes on the stream. Asked of a scanner in keyboard mode it is kept, either way, and the adapter asks for the scanner itself until it is set back (below). No scanner paired: the call fails, either way |
| `forget` (call) | forgets the paired scanner the package's status names |
| `start-pairing` (call, data `{venue, door, doorName}`, each optional) | starts pairing a scanner this phone has never used, and answers at once with `{kind: "pairing", step}`: `looking`, or the step of the pairing that already runs, which goes on. The data is where the scanner is paired; the package keeps it with the pairing, on the phone, beside iOS's id of the phone for the app's maker, which the shell adds |
| `stop-pairing` (call) | stops the pairing that runs |
| `events` (stream) | every event flat, with a kind: `read`, `failedRead` or `failedValidation` (with `fullName`, `dateOfBirth`, `expirationDate`, `isOver21`, `isExpired` when read; the document's own words, each when the document says it: `licenseNumber`, `sex` (`M`, `F` or `X`), `postalCode` and `issuingState` (below); `issueCode`, the first issue; and `scannerId`, the scanner's own id, when the scanner has given one (below)); `duplicate` (with `result`, the suppressed result's kind only); `unread` (nothing else: a scan, or its repeat, made while reading is stopped, so the page can say why nothing shows instead of showing nothing; one for each scan while the app is in front, to every open stream; none while the app is behind, and one when it comes to the front if any was made, however many); `state` (`state`; `paired`, 1 or 0, as the state call says it, on every one; and `reason` when the scanner is not connected: a real connection change, at once, and again when only the reason or only `paired` has changed, so a scanner forgotten, just paired, or unpaired outside the app is told without a call; the package's `reading` during each scan is held back and reads as `connected`); `battery` (`battery`, the percent); `warning` (`warning`: `keyboard-mode`, said once for each change of mode and to a stream that opens while it stands, or `low-battery`); `pairing` (`step`: `looking`, `connecting`, `confirm`, `paired` or `failed`, and with `failed` a `reason`) |

The adapter configures the package once, on first use: its age and expiry
checks on, its duplicate window as delivered, reporting off the phone never
configured. Nothing but the fields above leaves the adapter, and the shell
keeps only those the endpoint's `keep` names.

### The document's own words: its number, sex, postal code and issuing state

A read (and a read that failed its validation) says four fields more, by
the scanner package's own names where it has one, each handed to the page
only when the endpoint document's `keep` names it, exactly as written here:

| `keep` names | What the page is handed |
|---|---|
| `licenseNumber` | the document's number, as the document writes it, without padding |
| `sex` | `M`, `F` or `X`, as the document says it; a document that does not say it, or says it is not known, gives no field |
| `postalCode` | the postal code of the holder's address, without the padding a barcode gives it: nine digits whose last four are zeros are the first five (`999990000` is `99999`), nine others are five and four (`99998-1234`), and any other code is as written |
| `issuingState` | the two letters of the state or province that issued the document |

A field the document does not say is not in the event: there is no empty
value to read, and a gene's reader gives its own fallback. Each of the four
is said without its padding (spaces, tabs, new lines), and one that is
longer than 64 characters, or still holds a new line or another mark that
is no character, is not a word a document writes: it is no field, never a
part of it. What is said is a text, whatever is in it. A gene whose
endpoint names none of them is handed none of them, as before: the shell is
not told which field is personal and does not need to be, since it hands
over only what `keep` names and keeps nothing of a read itself, in no file,
no log and no defaults. Which of them is personal, and which may be written,
is the records' to say in `keep` (the engine holds a field marked personal
and not written on the phone). A `duplicate` and an `unread` say none of
them. The raw scan never leaves the binding, and of the document's other
elements the binding reads only the postal code (the package gives it no
name of its own). A customer's binding copied from
`Bindings/VendorIDScanner.swift` before these fields passes none of them on
and still builds: it is copied again to have them. The stand-in's three
made-up people say all four (`TEST0000001`, `F`, `99999`, `CA`; and so on),
so a rehearsal plays them. `scripts/check-reader.sh` holds each arriving
when `keep` names it and not arriving when it does not.

### The scanner's own id

A scan says one field of the scanner that made it, handed to the page only
when the endpoint document's `keep` names it, exactly as written here:

| `keep` names | What the page is handed |
|---|---|
| `scannerId` | the scanner's own id, as its package says it: the serial number the scanner itself gives, the same on every phone it is paired with |

It is the scan's and not the holder's: a `read`, a `failedRead` and a
`failedValidation` each say it, whether or not a document was read; a
`duplicate`, an `unread` and every other event do not. It is not the phone's
own name for the scanner (the peripheral's id, which iOS makes anew on each
phone and again when a scanner is forgotten and paired again): that id never
leaves the adapter. A scanner that has given no serial (the package reads
it from the scanner a moment after it first connects, and keeps it with the
pairing) gives no field: there is no empty value to read, and a gene's
reader gives its own fallback. It is said as a document's word is: without
padding, and one longer than 64 characters or with a mark that is no
character in it is no field. It says nothing of a person; whether it is
written is the records' to say in `keep`, as for every field. A customer's
binding copied from `Bindings/VendorIDScanner.swift` before this field
passes none on and still builds: it is copied again to have it. The
stand-in's made-up scanner says `TEST-SCANNER-0001` with each scan, so a
rehearsal plays it. `scripts/check-reader.sh` holds it arriving when `keep`
names it and not arriving when it does not.

### A paired scanner that is not connected: paired, the reason, at once

A gene's scanner pill must say within a second whether this phone has a
scanner and whether it is there (the first customer's request Q011), so:

- **`paired`** comes with every `state` answer, from the package's own list of
  paired scanners, read at the call, and with every `state` event on the
  stream, the same number. A state event is sent when only `paired` has
  changed: when the scanner is forgotten, when a first pairing is paired
  (after the pairing's last step), and, for a scanner unpaired in the phone's
  own settings, of which the package says nothing, when the app next comes
  to the front. A gene whose stream keeps `paired` needs no state call to
  know a scanner was unpaired while its page was open; one that does not
  keep it hears what it heard before.
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
- **A scanner in keyboard mode cannot be made into a loop.** The package
  refuses a connection to it and says the warning again each time. The
  adapter passes the warning on when the mode is first known, and not again
  until the scanner has been connecting or connected since, so a gene that
  answers the warning with a reconnect is not answered with another warning.
  A `reconnect` asked meanwhile is kept, not passed on as it comes: with
  `{wait: 0}` it answers at once with the state as it is (`disconnected`,
  `reason` `unknown`), with no data it answers when the scanner connects;
  and the adapter asks the package itself, at once and then every two
  seconds, since only asking says that the scanner was set back. Fifty
  reconnects in a second ask the package once. Set back, the scanner
  connects at the adapter's next try, with no tap. The tries end when it is
  connected or forgotten, and when the page's stream closes.

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

## Push

`Shell/Push.swift` is a native library of the shell's own, named `push`: the
three things of a push that only the phone can do. A gene reaches it as any
native library, by endpoint documents, and the shell does each only when a
record's call asks: it asks the person nothing, registers with nobody and
hands no token over at launch or by itself. No package of a push service is
in the shell or in a build of it, and no service's address or name: what a
service needs beyond these answers (its own token for this phone, a topic
the phone joins or leaves) is a call the gene's records make through the
engine, which the deployment signs.

| Endpoint | What the shell does, and answers |
|---|---|
| `native://push/permission` (call) | asks the person whether this app may notify them, and answers `{permission}`: `allowed` or `refused`. iOS shows its question the first time only; after that the answer it was given comes back with no question. With data `{ask: 0}` nothing is asked (the number 0, `false`, or either as a text; any other word asks): it answers at once what the person has said so far, `not-asked` when they have never been asked. A person who takes longer than the engine's limit for a call (30 s) to answer the question has answered it all the same: the call took its error hop, and a call after it reads what they said |
| `native://push/token` (call) | registers this phone with Apple and answers `{token, environment, app}`: the phone's push token as Apple gave it, in small hex; Apple's push environment the build is signed for, `development` or `production` (read from the build's own provisioning profile; a build from TestFlight or the App Store carries none and is `production`; a simulator's is `development`); and the app's own id, its bundle identifier. It needs no permission: a phone whose person refused has a token too, and is shown nothing. With no answer of Apple's in 25 seconds (a phone with no network hears nothing from Apple, neither way), or when Apple refuses (a build signed without the push entitlement), the call fails. Calls that wait together ask Apple once. The shell keeps the token nowhere: every call asks Apple, which hands a phone a new token now and then (a restore, a new install), so a gene asks each time its page arrives |
| `native://push/events` (stream) | every event flat, with a `kind`: `tap` (the person tapped a notification of this app; with `link`, the notification's own link, the text under `link` in its payload, when it has one) and `arrived` (a notification arrived while the app is on the screen; with `link` the same way). Nothing else of a notification is passed on |

- **A tap that opens an app that was closed** comes before any page has
  asked: it is kept, in memory, the last one only, and said to the first
  stream that opens. A tap said to a page that goes within three seconds
  of it (iOS ended its content while the app was behind, and the page loads
  afresh) is kept again and said to the page that loads, once: a tap is
  said to two pages at most, so a page that goes each time it hears one
  does not hear it for ever. A stream that only closes because its screen
  was left is no page going.
- **A notification that arrives with the app on the screen** is told to
  every open stream as `arrived`, and iOS then shows nothing over the page:
  the gene draws what it will. With no stream open nobody would tell the
  person, so iOS shows it as it does with the app behind (banner, list,
  sound).
- **With the app behind or closed** iOS shows a notification by itself, with
  nothing of the shell running; the shell hears of it only when it is tapped.
- The token is the phone's own name at Apple. It reaches the page only when
  the endpoint's `keep` names it, the shell keeps it in no file, no log and
  no defaults, and a development build's lines say which fields were handed
  over, never a value. Whether it is personal, and whether it may be written,
  is the records' to say in `keep`.

A build that is to have a token is signed with the push entitlement: its
lane's xcconfig sets `CODE_SIGN_ENTITLEMENTS = <this repository>/Config/Push.entitlements`
and nothing else. The file asks two things of Apple: `aps-environment`
(the Push Notifications capability) and
`com.apple.developer.usernotifications.time-sensitive` (so a notification
that says it is time-sensitive is shown as one). With automatic signing the
first archive turns both on for the app's id. A build that does not name the
file is signed as before, and its token call fails. Nothing else is set: no
key of a push service, no background mode.

The push environment the file asks is `INSPO_PUSH_ENVIRONMENT`, and it is
`development` for every build signed on a Mac (`Config/Default.xcconfig`):
a simulator's, one run from Xcode, and the archive. `scripts/archive.sh`
signs with the team's development profile, whose push environment is
`development`; a file that asked `production` would not match it, and Xcode
would stop the archive ("Provisioning profile ... doesn't match the
entitlements file's value for the aps-environment entitlement"). The upload
(`scripts/upload.sh`) signs the archive again for distribution and writes
`production` by itself, so a build from TestFlight or the App Store is a
production build with nothing set, and its token call says `production`
(read from the build's own profile, never from this setting). A lane leaves
the setting alone. This is by read of the two scripts and of what Xcode's
signing does: only an archive made with a team's signing proves it.

On a simulator (iOS 16 or later, on a Mac with Apple's own chip) the three
play with no phone: the question is iOS's own, Apple hands the simulator a
token of its development environment, and `xcrun simctl push <device>
<bundle id> <payload.json>` delivers a notification made on this Mac, to tap
or to see arrive. `scripts/check-push.sh` checks the library on this Mac,
with a phone that only records what it was asked.

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
