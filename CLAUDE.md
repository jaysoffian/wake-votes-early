# Wake Votes Early: notes for Claude Code sessions

Native SwiftUI app (macOS 14+ / iOS 17+, one multiplatform target) plus `wakevote-cli`, ranking Wake County
early-voting sites by drive there + published wait + drive back. README.md explains the product; this file
records decisions and gotchas that aren't obvious from the code.

## Build and verify

- `WakeVote.xcodeproj/project.pbxproj` is hand-written (objectVersion 77, synchronized folders `App/`, `Core/`,
  `CLI/`). New source files are picked up automatically; don't add PBXFileReference entries.
- Swift 5 language mode on purpose. Don't flip to Swift 6 / strict concurrency without being asked.
- macOS target is ad-hoc signed (`CODE_SIGN_IDENTITY[sdk=macosx*] = -`) so it runs with no team; iOS needs the
  user's team selected in Xcode.
- Inside the Claude Code sandbox, `xcodebuild`, the simulator, MapKit (`geod`) and Homebrew don't work.
  Type-check instead, calling the toolchain directly:
  ```sh
  TC=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin
  MACSDK=$(ls -d /Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk)
  IOSSDK=$(ls -d /Applications/Xcode.app/Contents/Developer/Platforms/iPhoneSimulator.platform/Developer/SDKs/iPhoneSimulator.sdk)
  $TC/swiftc -typecheck -disable-sandbox -module-cache-path "$TMPDIR/modcache" -sdk "$MACSDK" -target arm64-apple-macos14.0 -swift-version 5 -parse-as-library App/*.swift Core/*.swift
  $TC/swiftc -typecheck -disable-sandbox -module-cache-path "$TMPDIR/modcache-ios" -sdk "$IOSSDK" -target arm64-apple-ios17.0-simulator -swift-version 5 -parse-as-library App/*.swift Core/*.swift
  ```
  `-disable-sandbox` is required for SwiftUI/Observation macros. Real builds and simulator runs: the user runs
  them in Xcode, or via the Xcode MCP server (`xcrun mcpbridge`) if configured.
- The CLI can parse a saved Airtable response offline: `WAKEVOTE_FIXTURE=/path/to.json wakevote-cli`.

## Data sources and their constraints

- Wait times: Wake County's public Airtable shared view (no official API). `WaitTimeService` fetches the share
  page, regex-extracts the signed `readSharedViewData` URL, and calls it with the Airtable web-client headers
  (`x-airtable-application-id`, `x-requested-with: XMLHttpRequest`, etc.). The signed URL has an expiry (the
  one seen 2026-10-16 expires 2026-11-05); re-reading the page each refresh picks up renewals.
- Drive times: MapKit `MKDirections.calculateETA`, traffic-aware, no key. **MapKit throttles at ~50 ETA requests
  per 60 s per bundle ID, and the window survives relaunches.** Everything about `Planner.roundTrips`,
  `RequestThrottle` (40/min sliding window, persisted in UserDefaults) and the "8 exact return legs, rest
  estimated with ≈" design exists because of this. Don't add per-site requests casually.
- Return leg is requested for departure at now + drive + wait + `Planner.votingDuration` (15 min) so MapKit
  predicts traffic for when the user would actually leave.
- Site coordinates are baked into `SiteLocations.known` keyed by normalized address (Census geocoder + Google
  pins), with a CLGeocoder fallback cached in UserDefaults.
- Hours are county-wide and hard-coded in `EarlyVotingSchedule.wake2026General` (Oct 15–31 2026). Update for
  the next election.

## UX decisions the user has made (don't relitigate)

- One way to do each thing. The colored total-time capsule in a row *is* the directions button; no swipe
  actions, no context menus, no separate Directions button.
- iOS: no navigation bar. List/Map picker floats in a glass capsule at top; controls (address, location,
  Avoid tolls switch, status line) live in a glass sheet-style card at the bottom that runs to the screen
  edge. Refresh is pull-to-refresh only. macOS keeps a conventional toolbar (Avoid Tolls, Refresh ⌘R).
- Liquid Glass via `adaptiveGlass(in:)` / `softScrollEdges()` on iOS 26+, material fallback below.
- Row status is one sentence: exceptional state only (closes before arrival, no route) + live "Wait updated
  N ago" (`Text(_, style: .relative)` so it self-updates). Hours go in the footer, not per row, since all
  sites share them. The footer uses absolute times ("refreshed at 3:42 PM"), never a one-shot "now".
- Site names must wrap, never truncate ("Wake Technical Community College South Campus" needs 3 lines on an
  iPhone mini). Chips and status use `ViewThatFits` to stack on narrow screens.
- Show the wait-only ranking immediately after Airtable responds; drive times fill in when the batch finishes.
  Spinners cover only their own step; a new recompute cancels the in-flight one and keeps partial results.
- App icon is drawn in code (`Support/icon/icongen.swift`): yellow "WAKE VOTES EARLY" yard sign with red
  arrow. Product name is "Wake Votes Early"; display name is "Wake Votes Early" on macOS and "Vote Early" on iOS (APP_DISPLAY_NAME build setting with per-SDK override, referenced from Info.plist); bundle ID stays org.soffian.WakeVote (changing it
  would reset location permission and MapKit's per-app throttle state). Regenerate with the command in README.md; output goes to `App/Assets.xcassets/AppIcon.appiconset`.
- The user's Xcode had a stale Swift 5.7.1 toolchain override (`DVTDefaultToolchainOverrideIdentifer`); if
  builds fail with dependency-scan errors from `/Library/Developer/Toolchains`, that's why.

## Rejected iOS layout experiments (2026-10-16; don't propose again)

The user wanted the bottom card to take less space, but rejected each of these in turn. The current layout
(full-height glass bottom card with address field, location button, labeled "Avoid tolls" switch and status
line; glass List/Map capsule at top; pull-to-refresh; no navigation bar) is the one to keep. The attempts
remain in git history (commits 85e65d7e83, 4f9f889ebe, eaa4315154, reverted by 112e39b3ca) if a piece is
ever useful.

- Compact card with an icon-only toll toggle: "totally non-obvious." Controls need text labels.
- Card that collapses to one line when idle and expands on tap: "weird hybrid hack, not iOS-like."
- All-system layout with `.searchable` for the address, picker in the nav bar's principal slot, an Options
  menu holding Avoid Tolls, and the status as a list section header: "Yuck."
- Earlier: a `.button`-style Toggle in the iOS toolbar draws its own capsule inside iOS 26's glass toolbar
  group and looks broken; a one-item Menu for a single toggle is silly; the large navigation title and a
  separate Refresh button were removed as wasted space.
