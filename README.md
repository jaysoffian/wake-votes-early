# Wake Vote

Picks the fastest Wake County early-voting site for you: **drive there + current estimated wait + drive back**, ranked.
Native SwiftUI app for macOS and iOS from one Xcode project, plus a command-line tool that prints the same ranking.

## Run it

1. Open `WakeVote.xcodeproj` in Xcode 16 or newer.
2. Pick the **WakeVote** scheme and a destination:
   - **My Mac** runs immediately; the macOS build is ad-hoc signed, so no team is needed.
   - **Your iPhone** needs a team: select the WakeVote target → Signing & Capabilities → choose your Apple ID team. A free Apple ID works; the build expires after 7 days and you re-run from Xcode.
3. Press Run. Type a starting address and press Return, or tap the location button. The starting point is remembered between launches.

Toolbar: **Avoid Tolls** toggles toll-free routing (persisted; drive times recompute when you change it) and **Refresh** (⌘R) re-fetches everything. Wait times refresh every 5 minutes on their own; drive times are cached for 10 minutes per starting point and toll setting. Tap the directions icon on a row, or a pin on the map, to open Apple Maps.

If Xcode picks up an old Swift toolchain (build log shows `/Library/Developer/Toolchains/...`), switch it back with **Xcode › Toolchains › Xcode**.

### Command line

Same ranking, handy for testing:

```sh
xcodebuild -project WakeVote.xcodeproj -scheme wakevote-cli -configuration Release build
# then, from the build products folder:
wakevote-cli "123 Main St, Raleigh"             # or "35.78,-78.64"; omit for downtown Raleigh
wakevote-cli --no-tolls "123 Main St, Raleigh"
WAKEVOTE_FIXTURE=saved.json wakevote-cli ...    # parse a saved Airtable response instead of fetching
```

## How it works

- **Wait times** come from the county's public [Airtable tracker](https://airtable.com/appAL6KsUEvshj4br/shrQkIIFla4bjdGzh). There is no official API; the share page embeds a signed URL for Airtable's internal `readSharedViewData` endpoint, which returns JSON. See `Core/WaitTimeService.swift`. Buckets such as "5-15 Minutes" are scored at their midpoint.
- **Drive times** use Apple MapKit's traffic-aware ETA (`MKDirections.calculateETA`). No API key or account needed. The return leg is requested for the time you would actually leave (now + drive + wait + 15 minutes to vote), so MapKit predicts traffic for then.
- **Request budget.** MapKit allows about 50 ETA requests per minute per app, keyed by bundle ID and persisting across launches. The app fetches the outbound leg for every site but the exact return leg only for the 8 best candidates; the rest show "≈" and reuse the outbound time. A persisted sliding-window limiter (`Core/RequestThrottle.swift`) keeps the app under 40 requests a minute and queues the rest, and the footer reports when it is pausing. If MapKit throttles anyway, the app honors its reset timer. A new recompute cancels one still in flight and keeps what it already fetched.
- **Site coordinates** for the 18 general-election sites are baked into `Core/SiteLocations.swift`, keyed by address, with a CLGeocoder fallback for any site the county adds or renames.
- **Hours** are in `Core/Schedule.swift` (Oct 15–31 2026; weekdays 8:00–7:30, Sat 8:00–3:00, Sun 1:00–6:00). Sites that will be closed by the time you arrive are grayed out and sorted to the bottom.

## Layout

| Folder | Contents |
|---|---|
| `Core/` | Platform-neutral data layer shared by the app and CLI: Airtable client, MapKit ETAs, rate limiter, schedule, ranking |
| `App/` | SwiftUI app (`PlannerModel` owns the refresh loop; views for list and map) and the asset catalog with the app icon |
| `CLI/` | `wakevote-cli` entry point |
| `Support/` | Info.plist, plus `icon/icongen.swift` which renders the app icon from the extracted county site map |

The Xcode project uses synchronized folders, so new files dropped into `App/`, `Core/`, or `CLI/` are picked up automatically.

To regenerate the icon after editing the source map:

```sh
cd Support/icon
swiftc -O icongen.swift -o /tmp/icongen && /tmp/icongen wake-ev-map-2026-extracted.png ../../App/Assets.xcassets/AppIcon.appiconset
```

## Caveats

- The Airtable endpoint is unofficial. The signed URL currently embedded in the share page expires 2026-11-05; the app re-reads the share page on every refresh, so it follows whatever the county publishes until Airtable changes the page format.
- Wait estimates are updated by hand by county staff, typically every 30–60 minutes. The app shows how stale each one is.
- Only the Triangle Expressway is tolled in Wake County, so **Avoid Tolls** changes little for most starting points.
- For a future election, update the dates in `Core/Schedule.swift` and add any new sites to `Core/SiteLocations.swift` (or let the geocoder fallback handle them).
