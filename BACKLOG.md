# Backlog — features

Wanted, not built. Bugs live in `ISSUES.md`. Source: `verse-inbox.md` (2026-07-16).
Design north star: Apple's own apps (Music, Files) — take inspiration from their philosophy.

---

## Navigation: Home / Library tabs — **SHIPPED** (2026-07-17)

- ~~Move today's single screen into a **Library** tab.~~
- ~~New **Home** tab: big `Music` title, search bar beneath, playlists, most-played albums,
  most-played tracks.~~ `Sources/App/HomeView.swift`.
- ~~Bottom tab bar for Home + Library~~ — `Sources/App/RootView.swift`, which also owns the
  mini player and the player sheet so they survive tab switches and navigation.
- ~~Fold the options/burger menu into `+`, change that icon to **three dots**.~~ One
  `ellipsis.circle` menu on the Library tab.
- Play-count tracking landed with it: `playCount` / `lastPlayed` on `LibraryItem`, counted in
  `Coordinator.start`. This is the data Wrapped needs too.

"Album" is a folder that directly holds tracks — this library has no album tag, and the folder
tree is the organization. Revisit if real album metadata ever appears.

Still open here: more tabs (Locations, per Jellyfin below).

## Now Playing redesign — **SHIPPED** (2026-07-18, menu completed same day)

- ~~Minimize chevron instead of the drag bar~~ — top right in a dim circle (SoundCloud style).
- ~~Album art top-center, square corners.~~
- ~~Burger menu~~ — bare dots beside the title (Apple Music style): Info / Like / Share.
- ~~View Track / View Artist~~ — deep-links from the sheet into the Library stack
  (`Coordinator.DeepLink`; RootView flips the tab, LibraryView drives its `NavigationPath`).
  View Track = the track's folder (files only); View Artist = the ArtistPage.
- ~~AirPlay at the bottom~~ — Apple-Music bottom row: Lyrics · AirPlay · Queue.
- ~~Glass play button~~ (`glassEffect`).
- Lyrics is a fullscreen page: close top right, wave scrubber (real decoded audio via
  `Sources/Core/Waveform.swift` for AVFoundation-readable files, Files-style ticks for
  VLC-only codecs and streams), play bottom left, queue bottom right.
  2026-07-19: the scrubber moved **inside** the track pill (user request), and decoded
  waveforms now cache to disk (`Caches/waveform/`) — first open draws ticks until the decode
  lands, every later open is instant.
- Lyric-into-artwork rendering is **disabled by default** (user request, 2026-07-18): lock
  screen and CarPlay show real cover art. 2026-07-19: re-enable moved from a code flag to the
  Settings page.

## Mini player — **SHIPPED** (2026-07-17, revised 2026-07-18)

- 2026-07-18 shape (supersedes the rest): Apple Music pill — art left, title middle,
  **play + forward right**, **no swipe gestures**. Always attached, with a dimmed
  "Not Playing" idle state so the dock looks identical on boot and mid-song.
- Sits in `.tabViewBottomAccessory` (iOS 26) rather than a hand-rolled `safeAreaInset`, so it
  rides above the tab bar's glass pill instead of sitting flush under it. That container draws
  its own capsule and material — don't add a background inside it or you nest two capsules.
  An EMPTY accessory still renders a blank capsule — that's why the idle state exists.

## Library collections — **SHIPPED** (2026-07-18)

- Playlists / Artists / Albums / Songs rows on the Library root (Apple Music style, see
  `reference/music-library.png`), each a big-title page with a sort menu (Title / Date Added /
  Last Played / Most Played). `Sources/App/CollectionsView.swift`.
- Search is a dock pill (`Tab(role: .search)`) with its own page; no search bars on Home or
  Library. Guarded by `UITests/SearchTests.swift`.
- Favourites landed as its own collection row (2026-07-18), not a filter — liked tracks with
  the same sort menu.
- 2026-07-19: the collection rows are inlaid per the reference (user request) — no card
  behind them, big title, accent-tinted icon. The folder cards below keep the grouped look.
- Still open: grid/list toggle, Downloads filter, "imports" shelf on Home.

## Import flow "template" — decided 2026-07-18, not built

Pick made: **(a) import summary sheet** — before committing an import, show what was found,
where it goes, and a cover/metadata preview. Options (b) bulk metadata pass and (c)
`Artist - Title` filename parsing were declined. Related shipped piece: per-file
"Fetch Metadata" (embedded tags via AVAsset) in the hold menu; online lookup (MusicBrainz)
not built.

## App icon — **SHIPPED** (2026-07-17)

- ~~Replace with something new — a **CD or vinyl**.~~ CD after **`reference.jpg`** (the Yeezus
  cover): dark disc, vivid iridescence through the left and right sectors, near-black through top
  and bottom, soft radial streaks, and the solid red tape square across the right rim. Vinyl was
  drawn first and dropped.
- **The sheen and the red square are sanctioned exceptions to the no-gradient / monotone rules,
  and they are icon-only.** Those rules govern UI chrome (`.tint(.white)`, no colored chrome) and
  still hold everywhere else. Do not "fix" this icon by flattening or de-colouring it.
- `reference.jpg` in the repo root is the target. Compare against it before changing the drawing.
- 2026-07-18: sheen reduced to two hues (green/violet), five tonal steps, dark floor 0.12;
  red tape narrowed to the reference's 1.22 tall ratio.
- Regenerate with `Tools/makeicon.swift` (not in any target; see the header for the command).
  Current knobs: `SQH`/`SQL`/`SQR`/`SQC` (tape height / left edge / right edge / corner radius),
  `HUES`/`LEVELS` (sheen), `FLAT=1` for a no-sheen disc, `vinyl` as the style arg for the old one.

## Likes / favorites — **SHIPPED** (2026-07-18)

`LibraryItem.liked` toggles from the player's burger menu; browsing landed the same day as a
**Favourites** row on the Library collections (liked tracks, same sort menu).

## Settings / personalization — **SHIPPED** (2026-07-19)

User asked for "a feature heavy settings page to configure each personalization even add
themes". `Sources/App/SettingsView.swift`, gear on Home's toolbar. Keys in `Pref`, read by
core via the same constants:

- **Appearance / themes**: accent colour picker. **White stays the default** — the monotone
  rule still governs the stock look; non-white tints are a user-picked, Settings-sanctioned
  exception (same spirit as the icon carve-out).
- **Mini player**: optional wave scrubber in the dock pill (takes the artist line's slot, so
  the pill height never changes; drag to seek). Off by default — the Apple-Music pill stays
  stock.
- **Lyrics**: Lyrics on Artwork (the old `NowPlaying.lyricsInArtwork` flag) and CarPlay Text
  Fallback (`lyricsInTextFieldFallback`), both now UserDefaults-backed.
- **Playback**: SponsorBlock on/off (default on, registered in `Pref.registerDefaults()`).
- **Storage**: clear lyrics/artwork/waveform caches — also forgets the negative "nothing
  found" markers, so every track retries lookup on next play.

Not built: per-setting search, app-icon switcher, light mode (app is dark by design). Add if
ever asked.

## Jellyfin servers

- Connect to **Jellyfin** servers.
- Files-app-style **Locations** tab: browse and connect to a server alongside local folders.

## Wrapped — year-end listening recap

- Track plays over time (the data "most played" needs too).
- **Spotify-Wrapped-like** recap, shown at year end on the same date Spotify uses
  (~December 22), matching their tracking window.
