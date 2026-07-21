# Backlog — features

Wanted, not built. Bugs live in `ISSUES.md`. Source: `verse-inbox.md` (2026-07-16) through
`verse-inbox-3.md` (2026-07-20).
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
- Lyric-into-artwork rendering: disabled 2026-07-18, then **deleted entirely** 2026-07-19
  (user request). Lock screen and CarPlay always show the real cover; per-line lyrics live in
  the Live Activity, plus the optional CarPlay Lyrics artist-field toggle in Settings.

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
- 2026-07-20: rows **compressed 1:1** to `Reference/music-library.png` (inbox-3 — "compress"
  meant this table): extra vertical padding gone (~64pt → ~52pt rows), fixed 32pt icon column
  so labels align.

## Import flow "template" — decided 2026-07-18, not built

Pick made: **(a) import summary sheet** — before committing an import, show what was found,
where it goes, and a cover/metadata preview. Options (b) bulk metadata pass and (c)
`Artist - Title` filename parsing were declined. Related shipped piece: per-file
"Fetch Metadata" (embedded tags via AVAsset) in the hold menu; online lookup (MusicBrainz +
Cover Art Archive) shipped 2026-07-21 as an opt-in toggle (see In-place metadata below). The
pre-commit summary sheet itself is still unbuilt.

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
- 2026-07-19: sheen replaced with 14 colour stops sampled off the reference at the
  reference's own angles (dark top/right, green→silver upper-left, pink→cream lower-left,
  yellow bottom, magenta→violet lower-right); hard binary spokes, `HUES`/`LEVELS` knobs gone.
  Reference moved to `Reference/icon.jpg` (external rename).
- 2026-07-19: **alternate icons** — Settings › Appearance › App Icon: Red (default), Classic
  (the old green/violet disc), Purple (light MiniDisc after `Reference/icon2.jpg`, drawn by
  `makeicon purple`). Alternates live in `AppIcon-Classic`/`AppIcon-Purple` iconsets, wired via
  `ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES` in `project.yml`.
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
- **Lyrics**: CarPlay Lyrics toggle (`lyricsInTextFieldFallback` — current line in the artist
  field). The lyric-into-artwork renderer was **deleted entirely** (2026-07-19, user request);
  artwork is always the real cover.
- **Playback**: SponsorBlock on/off (default on, registered in `Pref.registerDefaults()`).
- **Storage**: clear lyrics/artwork/waveform caches — also forgets the negative "nothing
  found" markers, so every track retries lookup on next play.

Not built: per-setting search, app-icon switcher, light mode (app is dark by design). Add if
ever asked.

## In-place metadata — **PARTIAL** (2026-07-20, inbox-3)

Core shipped: import stores a bookmark per picked **root folder** (write access to the tree —
a file's own bookmark never covered siblings). Edits / Fetch Metadata / Like write
`<file>.verse.json` beside the track; resolved lyrics (incl. LRCLIB) export `<file>.lrc`
beside it. Re-import reads sidecars back and matches files by folder path + filename, so
identity, play counts, likes, and the id-keyed lyric/artwork caches survive. Guarded by
`Tests/SidecarTests.swift`. Folders imported before 2026-07-20 need one (loss-free)
re-import to gain a root bookmark.

2026-07-21 additions:
- **Import Files** — a second import option beside "Open from Files" (Library ellipsis menu):
  `.fileImporter` (multi-select, audio+video). Each file lands as a **loose** item with only
  its own minimal bookmark — no folder bookmark, so the folder is never associated. Such items
  have no directory scope, so their sidecar writes no-op and metadata stays in-app (marked with
  `ponytail:` at `writeTagsSidecar`/`exportLyricsSidecar`). `LibraryStore.add(pickedFiles:)`.
- **High-resolution album cover fetching + online metadata** — `Sources/Core/MetadataScraper.swift`:
  MusicBrainz recording search (title/artist/album) + Cover Art Archive `front-500` cover, no
  API key, `User-Agent` set. Gated behind **Settings › Metadata › Online Metadata** (default OFF,
  opt-in). Wired into `fetchMetadata`: embedded tags first, then online fill + hi-res cover into
  the `Artwork` cache. Pure parse guarded by `Tests/MetadataScraperTests.swift`.

2026-07-21, auto metadata + album association:
- **Auto metadata on import** — `LibraryStore.backfillMetadata()` runs after every import (both
  paths): reads embedded title/artist/album tags via AVAsset and fills what import left blank
  (filename parse / sidecar / user edits still win). New `LibraryItem.album` field.
- **Album grouping by tag** — the Albums collection now groups by `LibraryItem.albumKey`
  (album tag, else containing folder), not folder-only, so loose file imports gather into their
  album. New `AlbumRef` / `AlbumRow` / `AlbumPage` in `CollectionsView.swift`. Artists already
  group by the artist tag, now populated automatically.

2026-07-21, metadata-only browsing + rebuild insurance (user request: never show the import
folder or filenames; survive rebuilds; NO copying files into app storage):
- **Imported disk layout hidden.** `LibraryStore.visibleFolders(at:)` — browsing lists
  user-created folders only; imported source trees stay internal (identity, sidecar scope,
  album fallback). Home's album shelf + player "View Album" (was "View Track") + all
  collections navigate by `AlbumRef`/`ArtistRef` — metadata names, never paths/filenames.
  `mostPlayedAlbums()` is albumKey-based now.
- **Sidecars carry full state** — `SidecarTags` grew album/playCount/lastPlayed (optional,
  older sidecars decode). Written on edit, like, play, and auto-metadata backfill. Import
  restores all of it. So: app data wiped (re-sign, delete, new device) → re-import the folder
  → tags, albums, likes AND play history come back from beside the files. Bookmarks are the
  only thing iOS won't let us keep across a wipe; the sidecars make re-granting them a
  one-tap, zero-loss operation.

Still open:
- Hi-res / low-res version picker in Settings when duplicates of a track exist (needs
  duplicate detection first).
- Folder organize/rename macro driven by metadata.

## Colour settings — **SHIPPED** (2026-07-20, inbox-3)

- **Accent swatch group** — preset dots (White / icon Red `F0241C` / Yandhi Violet `96479E` /
  Blue / Green / Orange / Pink) above the custom ColorPicker in Settings › Appearance
  (`AccentSwatches` in `SettingsView.swift`). Presets live in `Pref.accentPresets`.
- **Colour From Cover** — Settings › Lyrics toggle (`Pref.lyricsCoverColour`): the active lyric
  line is tinted with the cover's dominant colour (`Artwork.dominantColor`, `DominantColorTests`).

## Lyrics page (inbox-3)

- "Enhance lyrics page, open to suggestions" — still open. Suggestions: art-tinted background,
  auto-scroll polish, word-level karaoke if LRCLIB richsync ever lands.

## LRCLIB lyrics import — **PLAN** (2026-07-21, not built)

Goal: proactively pull synced ("live") lyrics from LRCLIB into the app, not just lazily at
play time. LRCLIB is already wired (`LyricsResolver` chain: sidecar → embedded → LRCLIB →
negative cache; `LRCLibClient` in `Lyrics.swift`; results cache to `Caches/lyrics/<uuid>.lrc`
and export a `<file>.lrc` sidecar for folder imports). This plan is about surfacing + batching
it, and improving match quality.

Phased, laziest-first:

1. **Duration-matched lookup (cheap, biggest quality win).** `LyricsResolver.resolve` passes
   `duration: nil` today, so LRCLIB can only fuzzy-search. Load `AVURLAsset.load(.duration)`
   before the call (we already do this in the info panel) and pass it, so `LRCLibClient` can hit
   the exact `/api/get?...&duration=` endpoint first, falling back to `/api/search`. No UI.

2. **Per-track "Fetch Lyrics" (hold menu).** Add to `ItemContextMenu` next to "Fetch Metadata":
   invalidate the negative cache for that track, run the resolver, cache + export sidecar. One
   item, on demand. Reuses everything that exists.

3. **Lyrics status on rows.** A small glyph in `ItemRow` (e.g. `quote.bubble` filled/none) from
   a cheap synchronous `LyricsResolver.cachedRaw(key:)` check — synced vs plain vs none — so the
   user can see coverage at a glance. Ties into #4.

4. **Library-wide batch fetch.** A "Fetch All Lyrics" action (Settings › Lyrics, or the Library
   ellipsis). Iterate items missing lyrics, call the resolver serially with LRCLIB politeness
   (~1 req/s, like the metadata scraper), show a progress overlay + a cancel. `ponytail:` serial
   loop, not concurrent — LRCLIB is a free community instance, don't hammer it.

5. **Manual paste / edit.** A lyrics editor sheet (paste raw LRC or plain text) reachable from
   the player's lyrics page and the hold menu; save via `LyricsResolver.attach(lrcText:key:)`
   (already exists) + sidecar export. Covers tracks LRCLIB doesn't have.

Constraints: LRCLIB only (no new dependency, no key); file-imported loose items can't write a
`.lrc` sidecar (no directory scope) so their lyrics stay in the cache — same ceiling as tags.
Keep `LyricsTests` green; add a duration-query builder test for phase 1.

2026-07-21: **phase 4 essentially shipped** as part of `LibraryStore.onlinePass()` — runs after
every import and via Settings › Library › **Rescan Library**: serial LRCLIB resolve per track,
cached + exported to `.lrc` sidecars (no separate progress overlay; the Rescan row shows a
spinner). Same pass fills albums + hi-res covers when Online Metadata is on. Single-track
lyrics also ride "Fetch Metadata" now. Still open: phases 1 (duration-matched lookup),
2 (dedicated Fetch Lyrics menu item), 3 (row status glyph), 5 (manual paste/edit).

## Shipped 2026-07-21 (late batch)

- Numeric-aware title sorting everywhere (`localizedStandardCompare`) — numbered tracks play
  sequentially.
- **Album detail page**: 220pt cover, artist line, track count, Play/Shuffle, numbered rows.
- Settings › **Library** section: imported folder list, **Show File Locations** toggle
  (`Pref.showFilePaths` — brings the disk tree back into browsing), **Rescan Library**.
- Library ellipsis menu grouped into **Import** / **Add Link** submenus.
- `verse-prompt.md` — verbatim log of commanding prompts (gitignored); standing rule to append
  each one, same turn.
- **Pastel pass** (user-sanctioned icon change): Yeezus + Classic disc interiors pastelised
  (`pastel()` remap in `Tools/makeicon.swift` — unlit sectors and spokes stay dark, bands stay
  posterised; Yandhi untouched). Accent presets now pastel; Violet preset = the exact Yandhi
  tape colour (`97479E`).
- Settings reordered: **Library section first**; **Import Folder / Import Files moved into
  Settings › Library** and removed from the Library tab menu (which keeps Add Link / Select /
  New Folder / Sort).
- Batch 5 (2026-07-21): all audit suggestions shipped — issues #7 (AirPlay scope leak) and
  #8 (coverless-audio VLC surface) fixed; queue persists across launches; per-track resume
  position; sleep timer; LRCLIB duration-matched lookup; library backup export. Plus: Settings
  pushed from Library's top-left gear (tab removed); uniform `.headline` inline titles; Home
  shelves ordered + hold-header edit (move/remove) + Add Shelf + album grid size knob; Home
  album-grid triple-swipe-back bug fixed (multi-push NavigationLink → path-driven Buttons);
  Fetch Metadata / Fetch Artwork split; Tinted Background toggle; sidecar location control
  (beside files or picked folder); "In the Works" section in Settings mirrors this backlog.
- Batch 6 (2026-07-21): **fetch-never-worked root cause fixed** — the MusicBrainz query
  emitted `artist:""` for tracks with no artist tag (all filename-parsed ones), matching
  nothing; empty fields are omitted now (`MetadataScraper.buildQuery`, `QueryBuilderTests`),
  quotes stripped, per-track politeness sleep added, and a **persistent result summary**
  ("Artwork: 12 found, 3 not matched") stays under the Settings buttons. Library menu:
  **Import From** submenu (Folder / Files / YouTube / Spotify / SoundCloud). Shared
  **NowPlayingCard** (widget-shaped, wave-scrubber pill beneath) on Home AND the Queue sheet.
  Home **Edit mode** (Edit/Done, iPhone-style minus badges per `Reference/homepage/`) + album
  shelf size in its hold menu. **iPod Mode beta toggle** (Appearance) → click-wheel skeleton
  (`IPodView.swift`, layout after keremersu35/iPodPlayer; wheel scroll + menu tree = future).

- Batch 7 (2026-07-21): artwork cache bumped to 600px and forced Fetch Artwork upgrades every
  cover (not just missing); Home editing is hold-only (no toolbar buttons — hold a shelf →
  Edit Home Screen: minus badges, per-shelf size pills, Add + Done section); per-shelf sizes
  (`home.shelfSizes`) — Now Playing small/medium/large card, album grid 3/2/1 columns, list
  shelves 3/6/10 rows; Library rows compressed to the floor (28pt thumbs, 1pt insets).

## Stem Player — **PLAN** (2026-07-21, not built)

Per-stem playback (vocals/drums/bass/other) like the Kanye Stem Player. Reference repos:
`krystalgamer/stem-player-emulator` (device behaviour, reverse-engineered),
`lukew3/stemPlayerOnline` (UI), `Frikallo/MISST` + `stemdeckapp/stemdeck` (separation tools —
both drive Demucs-class ML models).

Lightweight-first phases:
1. **Play pre-separated stems** — a folder/album containing `*-vocals.*`, `*-drums.*`,
   `*-bass.*`, `*-other.*` (MISST/stemdeck output naming) gets a Stems view: 4 vertical
   sliders, per-stem volume/mute, synced playback. VLC can't mix 4 streams sample-locked —
   use 4 × AVAudioPlayerNode on one AVAudioEngine (AVFoundation-decodable formats only).
   No new dependency, no ML. This is the 90% feature.
2. **Stem-file import UX** — detect stem sets at import, group as one track with a stems badge.
3. **On-device separation** — Demucs-class model via CoreML. Heavy (hundreds of MB, minutes
   per track); only if ever justified. Server-side/offline separation via MISST on a computer
   stays the recommended path; the app just plays the results.

- **iPod mode** (2026-07-21: **skeleton shipped** — Appearance beta toggle, click-wheel
  layout, working menu/prev/next/play buttons. Still open: wheel rotary scrolling, the menu
  tree, cover-flow): an Appearance slider/toggle that turns the app
  into a classic-iPod-style interface (click-wheel-ish navigation, monochrome list chrome).
  Future work — parked here on request.
- Batch 3 same day: hold-menu reworked (Fetch Lyrics + Add to Playlist replace Edit / Move /
  Fetch Metadata); **local playlists** (`LocalPlaylist`, playlists-local.json, page + rename /
  delete, "+" on the Playlists page); Share now attaches `<file>.verse.json` + `.lrc` alongside
  the audio; Queue: always-on drag handles (no Edit button), swipe delete, 44pt album covers;
  **Deezer artist portraits** on ArtistPage (keyless, cached as `artist-<name>`), so artist and
  album pages read differently; `[[verse-prompt]]` linked from inbox-3 for Obsidian navigation.
- Batch 2 same day: Verse icon reverted to dark (pastel = Yeezus only); Settings swipe-remove
  imported folders; always-online **Fetch Covers & Metadata** + **Fetch Lyrics** buttons
  (bypass the toggle, clear negative caches); lyrics font + size in Appearance; custom accent
  presets (save/hold-to-remove); Queue sheet redesigned (black, Now Playing pinned, reorder +
  swipe-remove); hold-menus on all collection pages; ArtistPage is a profile page (circle art,
  albums, songs); Library rows compressed again (36pt thumbs).

## Jellyfin servers

- Connect to **Jellyfin** servers.
- Files-app-style **Locations** tab: browse and connect to a server alongside local folders.

## Wrapped — year-end listening recap

- Track plays over time (the data "most played" needs too).
- **Spotify-Wrapped-like** recap, shown at year end on the same date Spotify uses
  (~December 22), matching their tracking window.
