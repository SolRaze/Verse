# Verse inbox 2

Notes stay here permanently, same rules as `verse-inbox.md`: each gets a status line as it's
triaged or built. Legend: **DONE** · **PARTIAL** · **ISSUE** · **BACKLOG**.
Last triage: 2026-07-18. Reference screenshots live in `reference/`.

---

also on boot without mini player dock appears different after mini player is executed it expands in size i wan it to retain same state on boot every time bro

> **DONE** (2026-07-18) — the mini player bar is now ALWAYS attached (Apple-Music style): on
> boot it shows a dimmed "Not Playing" state, so the dock is identical before and during
> playback. This replaces the earlier only-while-playing behavior from inbox-1.

a bug occurs when minimizing search bar and it shows a bad circle and does not show typed input and functions overall bad

> **DONE** (2026-07-18, second pass) — first fix (drawer-pinned field) made the clear (x)
> button break the field: the pinned drawer field was fighting the search tab's own bottom
> field. Reverted to plain system `.searchable` placement. Now guarded by a real UI test
> (`UITests/SearchTests.swift`: open search, type, clear, retype) — passes on the 26.5 sim.

display a playlists, artist, albums and songs tab that when clicked opens into a new tab with dame format as home page but with a sorting menu at top check apple music for this i want it as same as that

> **DONE** (2026-07-18) — per `reference/music-library.png`: Library's root now opens with
> Playlists / Artists / Albums / Songs rows, each a big-title page with a sort menu top right
> (Title / Date Added / Last Played / Most Played, per `music-playlist-menuoption3.png`;
> playlists sort by title). Artists get their own per-artist track page. Remote playlists
> moved off the Library root into the Playlists page. New file `Sources/App/CollectionsView.swift`.
> Not built: grid/list toggle, Favourites/Downloads filters — **BACKLOG** if wanted.

remove search bar from library and implement a template like format when importing open for suggestions on this, the burger menu icon in library needs change find just dots without circle

> **PARTIAL** (2026-07-18) — Library search bar removed (dock search pill owns search); burger
> is now bare `ellipsis`, no circle, in both Library and the player. Still open: "template like
> format when importing" — unclear what template means. Suggestions: (a) an import summary
> sheet (what was found, where it goes, cover/metadata preview) before committing; (b) a
> post-import "fetch metadata for all" pass; (c) naming templates like `Artist - Title` parsing.
> 2026-07-18: user picked **(a) summary sheet** → **BACKLOG** (import flow), not built yet.

even inside the fullscreen player, rework on all move the button positions check soundcloud and apple music for the inspiration if needed i have provideed screenshots as reference

> **DONE** (2026-07-18) — per `soundcloud-player.png` + `music-player.png`: minimize chevron
> top right in a dim circle (SoundCloud), title/artist left with the bare-dots burger beside
> them (Apple Music), scrubber, transport with the glass play button, and an Apple-Music bottom
> row: Lyrics · AirPlay · Queue. Queue opens the Up Next sheet from anywhere in the player.

same when clicking lyrics make it spotify like, and the sound scrubber inside the mini player with a wave data instead of bar and button and no name, check files for this

> **DONE** (2026-07-18, second pass) — first pass put the tick scrubber in the mini player;
> user reverted that: mini player is back to the Apple-Music pill (art / title / play+forward),
> and the wave scrubber lives ONLY on the lyrics page. It now draws REAL audio
> (`Sources/Core/Waveform.swift`: AVAssetReader → RMS buckets) for AVFoundation-decodable local
> files; VLC-only codecs (ogg/opus/ape) and remote streams fall back to Files-style ticks —
> VLC exposes no decoded samples, that ceiling stands. Lyrics page stays Spotify-shaped.
> Also in this pass: lyric-into-artwork rendering DISABLED entirely (user request) — lock
> screen and CarPlay always show real album art now; `NowPlaying.lyricsInArtwork = true` brings
> karaoke artwork back. Live Activity lyrics unaffected.

need a feature to fetch metadata for files and update them accordingly

> **DONE** (2026-07-18) — "Fetch Metadata" in a file's hold-menu: re-reads embedded tags
> (title, artist) and cover art via AVAsset and updates the item. Embedded tags only — online
> lookup (MusicBrainz etc.) is **BACKLOG**.
