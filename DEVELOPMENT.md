# Development notes

## Building

- Open `WakeVotesEarly.xcodeproj` in Xcode 16 or newer and pick the **WakeVotesEarly** scheme (checked in under `xcshareddata`).
- **My Mac** runs with no signing setup (the macOS build is ad-hoc signed).
- **Your iPhone** needs a team: WakeVotesEarly target → Signing & Capabilities → choose your Apple ID. A free Apple ID works; the install expires after 7 days.
- The project uses synchronized folders, so files added to `App/`, `Core/`, or `CLI/` are picked up automatically.
- If the build log shows a compiler under `/Library/Developer/Toolchains/`, Xcode is using an old toolchain override. Switch back with **Xcode › Toolchains › Xcode**.

## Testing outside voting hours

Two debug-only environment variables are predefined (disabled) in the scheme under **Run › Arguments › Environment Variables**. Enable them as needed; neither exists in release builds.

| Variable | Effect | Preset value |
|---|---|---|
| `WVE_NOW` | Overrides the current time (ISO 8601) for the schedule, the ranking's arrival checks, and the hours text. | `2026-10-16T14:30:00-04:00`, a weekday afternoon in the period |
| `WVE_FIXTURE` | Loads a saved Airtable response instead of fetching wait times. | `$(SRCROOT)/Support/fixtures/airtable-2026-10-16.json`, real waits from that afternoon |

Typical uses:

- **Realistic rows after hours:** enable both. Drive times still come from MapKit, predicted for the faked departure time.
- **The "early voting ended" screen:** enable `WVE_NOW` with a value after `2026-10-31T15:00:00-04:00`, for example `2026-11-01T10:00:00-04:00`. A value after Election Day (`2026-11-04T10:00:00-05:00`) hides the Election Day line.
- **A closed day:** `2026-10-18T20:00:00-04:00` (Sunday evening) shows the closed state and the next opening.

The fixture's "wait updated" timestamps are shifted on load so the newest reads "2 min ago" against the real clock, with the original spread between sites preserved. Note that `xcrun simctl status_bar … --time` only repaints the status-bar clock; it does not change the time the app sees.

## Simulator location

The simulator has no location until you give it one: **Features › Location › Custom Location…**. A neutral downtown starting point is the North Carolina State Capitol:

```
1 East Edenton Street, Raleigh, NC 27601
Latitude   35.780406
Longitude -78.639145
```

Then tap the app's location button, or type the address.

## Screenshots for App Store Connect

- Required size is the 6.9-inch iPhone: **1320 × 2868** pixels. Use an iPhone 18 Pro Max or 17 Pro Max simulator and **File › Save Screen** (⌘S). Files land on the Desktop by default (**Simulator › Settings** changes that; it ignores the macOS screenshot location).
- Clean status bar before capturing:
  ```sh
  xcrun simctl status_bar booted override --time 9:41 --batteryLevel 100 --cellularBars 4 --wifiBars 3
  ```
- The simulator's own screen recording doesn't capture taps. For a video with touch indicators, enable the overlay and record the Simulator window with macOS screen recording (⇧⌘5):
  ```sh
  defaults write com.apple.iphonesimulator ShowSingleTouches -bool true   # relaunch the Simulator
  ```
  App Previews are optional; screenshots are required.

## App icon

The icon is drawn in code. After editing `Support/icon/icongen.swift`:

```sh
cd Support/icon
swiftc -O icongen.swift -o /tmp/icongen && /tmp/icongen ../../App/Assets.xcassets/AppIcon.appiconset
```

Clean Build Folder afterwards; Xcode and the Dock cache icons aggressively.

## Command-line tool

`wakevotesearly-cli` prints the same ranking and is mainly a test harness for the shared `Core/` code.

```sh
xcodebuild -project WakeVotesEarly.xcodeproj -scheme wakevotesearly-cli -configuration Release build
wakevotesearly-cli "1 East Edenton Street, Raleigh, NC"   # or "35.780406,-78.639145"
wakevotesearly-cli --no-tolls "35.780406,-78.639145"
WAKEVOTE_FIXTURE=Support/fixtures/airtable-2026-10-16.json wakevotesearly-cli ...
```

## Working on it with Claude Code

Xcode ships an MCP server that lets an agent build, run, and read issues through Xcode itself. Enable it in **Xcode › Settings › Intelligence › Model Context Protocol**, then register it from this directory:

```sh
claude mcp add --transport stdio --scope project xcode -- xcrun mcpbridge
```

`CLAUDE.md` records design decisions and build gotchas for future sessions.

## Next election

- Dates and hours: `Core/Schedule.swift` (`EarlyVotingSchedule.wake2026General`, including Election Day).
- Sites: `Core/SiteLocations.swift` holds coordinates and the county's per-site "Site Details" PDF names, keyed by address. Unknown addresses fall back to CLGeocoder.
- The Airtable share URL in `Core/WaitTimeService.swift` if the county publishes a new tracker.
