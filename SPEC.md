# Roadie — build brief

Target: iPhone 17e, iOS 26. Swift 6, SwiftUI. Sideloaded, single user (me). No App Store, no
accounts, no analytics, no onboarding, no settings screen unless a setting is load-bearing.

Read `README.md` first. The CarPlay constraints there are facts, not opinions. If a task below
seems to conflict with them, the constraints win.

## Scope

1. Play any media file from the Files app — audio or video, any container, any codec.
2. Play YouTube without ads.
3. Show time-synced lyrics, sourced from LRCLIB, embedded tags, or a sidecar `.lrc`.
4. Surface all audio on the CarPlay Now Playing screen, with lyrics rendered into the artwork.

Anything not on that list is out of scope. No playlists-of-playlists, no cloud sync, no themes,
no library database beyond what's needed to find a file again.

## 1. Playback engine

Use **MobileVLCKit** as the single engine for everything. Not AVPlayer, not a two-engine split.
VLC decodes mp3, aac, alac, flac, opus, ogg, wav, aiff, wma, ape, m4a, mp4, mkv, avi, mov, webm,
hls, and the long tail. One engine means one now-playing integration and one set of bugs.

`Sources/Core/Player.swift` has the wrapper. Requirements:

- `AVAudioSession` category `.playback`, `.mixWithOthers` off, activated on first play. Background
  audio mode in Info.plist. Without this there is no CarPlay and no lock-screen playback.
- Expose `@Published` state: current item, position, duration, isPlaying. Poll VLC's time via its
  delegate, not a timer, where possible.
- Video renders into a `UIViewRepresentable` host on the phone only. Do not attempt to route it to
  an external screen.
- Seek, rate, and next/prev must be driven from `MPRemoteCommandCenter` as well as the UI — the
  car's steering-wheel buttons go through the remote command center, not your views.

## 2. Files

- `UIDocumentPickerViewController` (`.open`, multiple) for import. Keep **security-scoped
  bookmarks**, not paths — paths go stale and the app loses access after a relaunch. Resolve the
  bookmark and `startAccessingSecurityScopedResource()` before every play, stop after.
- Set `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` in Info.plist so files can be
  dropped straight into the app's Documents folder from Files.app or a Mac.
- Register document types / `CFBundleDocumentTypes` broadly (`public.audio`, `public.movie`,
  `public.data`) so "Open in Roadie" appears in the share sheet.
- Library persistence: a single `Codable` array of items written to a JSON file. Not Core Data,
  not SwiftData, not SQLite. It's a personal library, it fits in memory.

## 3. Lyrics

`Sources/Core/Lyrics.swift` is written. It has the LRC parser and the LRCLIB client. Wire it up:

Resolution order for a track — first hit wins:
1. Sidecar file: same basename, `.lrc` extension, next to the media file.
2. Embedded tags: ID3 `SYLT` (synced) or `USLT` (unsynced); Vorbis comment `LYRICS`. Read via
   `AVAsset.metadata` where possible.
3. LRCLIB: `GET https://lrclib.net/api/get` with `artist_name`, `track_name`, `album_name`,
   `duration` (seconds, integer). Returns `syncedLyrics` (LRC text) and `plainLyrics`. 404 means
   no match — fall back to `GET /api/search?q=` and take the best duration match.
   No auth, no key. Send a real `User-Agent` — LRCLIB asks for one.
4. Nothing. Show the plain lyrics if present, otherwise an empty state. Do not fake timings.

Cache resolved lyrics on disk keyed by the track's stable id so the car isn't waiting on network.

The user also drops `.lrc` files directly — treat a `.lrc` import as "attach to the track whose
basename matches", and if none matches, keep it unattached and let them pick.

## 4. YouTube

- Extraction: **YouTubeKit** (`github.com/alexeichhorn/YouTubeKit`, SPM). Ask it for streams,
  pick highest-bitrate audio-only for car use, or a muxed/adaptive video stream for phone use.
- Ads: extraction fetches the media stream directly, so pre-roll and mid-roll ads never enter the
  pipeline. There is no ad-blocking code to write — this falls out of not using the YouTube player.
- **SponsorBlock** for in-video sponsor reads:
  `GET https://sponsor.ajay.app/api/skipSegments?videoID=<id>&category=sponsor&category=selfpromo&category=interaction`
  Returns segments as `[[start, end], ...]` in seconds. During playback, when position enters a
  segment, seek to its end. That is the whole feature.
- Input: paste a URL, or accept a share-sheet extension from the YouTube app (Info.plist URL
  types + a share extension is optional — start with paste).
- Extraction fails often and loudly. Surface the error. Never crash, never silently show a blank
  player.

## 5. CarPlay — the only part that is subtle

`Sources/Core/NowPlaying.swift` is written. It does two things:

**a. Standard now-playing info.** Title, artist, album, duration, elapsed time, playback rate.
Keep `MPNowPlayingInfoPropertyElapsedPlaybackTime` accurate on every state change or the car's
scrubber drifts. Register handlers on `MPRemoteCommandCenter` for play, pause, toggle, next,
previous, changePlaybackPosition, skipForward/Backward.

**b. Lyrics rendered into the artwork.** On each lyric-line change, render a `UIImage` containing
the previous / current / next lines (current line emphasized) and republish `nowPlayingInfo` with
a fresh `MPMediaItemArtwork` wrapping it. The car shows it big.

Known rough edges — test in the actual car, not the simulator:
- Some head units cache artwork aggressively and won't refresh per-line. If yours does, fall back
  to pushing the current lyric line into `MPMediaItemPropertyArtist` or `AlbumTitle` — text fields
  update reliably where images may not.
- Don't republish faster than lines actually change. LRC lines are seconds apart; that's fine.
  Do not run this off a 60Hz display link.
- Fall back to real album art the moment lyrics are absent.

There is no `CPTemplateApplicationSceneDelegate` in this project. If you find yourself writing one,
you have gone down the entitlement path — stop.

## Verification

Non-negotiable, because this is a driving app and I can't debug it at 70mph:

- `Tests/LyricsTests.swift`: LRC parser round-trip — timestamps `[mm:ss.xx]` and `[mm:ss.xxx]`,
  multiple timestamps on one line, metadata tags (`[ar:]`, `[ti:]`, `[offset:]`), blank lines,
  out-of-order lines, and `lineIndex(at:)` boundary behavior at 0, exactly-on-a-timestamp, and
  past the last line. Use placeholder text, not real lyrics.
- A `demo()` that plays a local file, prints now-playing dict transitions, and asserts elapsed
  time tracks position.
- Manual: plug into the car. Confirm play/pause from the wheel, scrubber accuracy, and whether
  artwork refreshes per line on that specific head unit.

## Conventions

- No dependency gets added without it replacing more code than it costs. Current list is final:
  MobileVLCKit, YouTubeKit. Everything else is Foundation/AVFoundation/MediaPlayer/SwiftUI.
- Mark deliberate shortcuts with a `ponytail:` comment naming the ceiling and the upgrade path.
- Fewest files that work. Do not scaffold for a future that may not arrive.
