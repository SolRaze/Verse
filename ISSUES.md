# Issues — open problems

Defects only. Features live in `BACKLOG.md`. Source: `verse-inbox.md` (2026-07-16) plus
session findings. No GitHub remote on this repo, so this file is the tracker.

---

## 1. Spotify / SoundCloud playlist links fail to import

**Symptom** — alert: *"Something failed"* → *"Spotify/SoundCloud gave a page this app no longer
understands — the scraper needs updating."*

**Where** — `Sources/Core/Playlists.swift`: `spotifyPlaylist(id:sourceURL:)`,
`soundcloudSet(url:)`, surfaced via `Coordinator.lastError`.

**Notes** — the fetchers are not wholly broken: `testSpotifyPlaylistFetch` (editorial
"Today's Top Hits") and `testSoundCloudSetFetch` (`/flume/sets/skin`) both pass on device.
So this is a coverage gap, not a dead scraper. Suspects:

- **Spotify** — parser keys on a `trackList` array inside the embed `__NEXT_DATA__`. Likely
  differs for user-created playlists. `spotify.link` short URLs, `/album/`, and `/track/`
  URLs aren't handled at all (only `/playlist/`).
- **SoundCloud** — only `/sets/` resolve to an object with a `tracks` array. A track URL,
  a likes page, or a user profile returns something else → `parseFailed`.

**Fix direction** — resolve short links via redirect; accept album/track/user URLs; tolerate
alternate JSON shapes; make the error name what's actually unsupported.

---

## 2. YouTube playlist import stops at ~100 items

**Where** — `Playlists.swift` → `youtubePlaylist(id:sourceURL:)`. First innertube page only;
continuation tokens are never followed (there's an existing `ponytail:` comment saying so).

**Fix direction** — follow `continuationItemRenderer` tokens until exhausted.

---

## 3. Video playback disabled during playback

**From inbox** — *"video playback disabled currently when playing."*

**Status** — needs clarification; can't reproduce from the description. Which screen, and
disabled how (controls greyed, black frame, or won't start)? Suspect the YouTube-playlist
path: `Coordinator.play(_ playlist:at:)` marks entries `isVideo` only for
`.youtubeChannel`, so playlist entries route audio-only through VLC by design — video never
shows for them.

---

## 4. Playback start and library recall are slow

**From inbox** — *"music playback and its recalling feature takes time to load content."*

**Suspects** (all on the pre-play path in `Coordinator.start(_:)`):
- `LyricsResolver.resolve` hits the network (LRCLIB) before `player.load`.
- YouTube items re-extract every play (by design — stream URLs expire) and can also cost a
  `youtubeSearch` for Spotify/SoundCloud entries.
- `LibraryStore.backfillArtwork()` resolves every bookmark and opens every file after import.

**Fix direction** — start playback first, resolve lyrics/artwork async and attach when ready.

---

## 5. Swipe-back needs two swipes on folder screens

**Status** — unresolved; reported again after two attempted fixes.

**Tried** — (a) plain `List` instead of `List(selection:)` while browsing; (b) injecting
`.environment(\.editMode,)` only in Select mode. Both in `Sources/App/LibraryView.swift`
→ `FolderView`.

**Next suspect** — the bottom `.safeAreaInset` carrying `MiniPlayerBar`/`BatchBar`, a known
interactive-pop offender. Needs a data point: does it glitch when nothing is playing (inset
content is empty) or only with the mini-player visible?
