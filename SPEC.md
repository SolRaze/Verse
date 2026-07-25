# Verse — the brief

target is iphone 17e, ios 26. swift 6, swiftui. sideloaded, single user, that user is me. no app
store, no accounts, no analytics, no onboarding, and no settings screen for a setting that isnt
carrying weight.

read `README.md` first. the carplay constraints in there are facts not opinions, and if something
below looks like it conflicts with them then the constraints win, always.

## scope

1. play any media file from the files app — audio or video, any container, any codec.
2. play youtube without ads.
3. show time synced lyrics from LRCLIB, embedded tags, or a sidecar `.lrc`.
4. put all audio on the carplay now playing screen with lyrics rendered into the artwork.

anything not on that list is out of scope. no playlists of playlists, no cloud sync, no themes, no
library database beyond what it takes to find a file again. dont scope creep this bro.

## 1. playback engine

**MobileVLCKit** runs everything except one carve out. vlc decodes mp3, aac, alac, flac, opus, ogg,
wav, aiff, wma, ape, m4a, mp4, mkv, avi, mov, webm, hls and the whole long tail. one engine means
one now playing integration and one set of bugs instead of two.

the carve out: **video that can reach the car screen goes thro AVPlayer**
(`Sources/Core/AirPlayVideo.swift`, already written). ios 26 airplay video in the car only works
thro avplayer external playback — vlc decodes locally so it cannot airplay video, thats a hard
wall not a preference. the routing rule is `AirPlayVideoPlayer.canAirPlay(url)`: avplayer
compatible containers (mp4/m4v/mov/HLS — every extracted youtube stream qualifies) take the
avplayer path with an `AirPlayButton` in the ui, everything else uses vlc on the phone screen.
do NOT widen the avplayer path past this.

`Sources/Core/Player.swift` has the wrapper. what it needs:

- `AVAudioSession` category `.playback`, `.mixWithOthers` off, activated on first play. background
  audio mode in Info.plist. without this theres no carplay and no lock screen playback at all.
- expose `@Published` state: current item, position, duration, isPlaying. poll vlcs time thro its
  delegate not a timer wherever you can.
- video renders into a `UIViewRepresentable` host on the phone only. do not try to route it to an
  external screen, see above.
- seek, rate and next/prev have to be driven from `MPRemoteCommandCenter` as well as the ui — the
  steering wheel buttons go thro the remote command center, not thro your views.

## 2. files

- `UIDocumentPickerViewController` (`.open`, multiple) for import. keep **security scoped
  bookmarks**, never paths — paths go stale and the app loses access after a relaunch, which is
  exactly the bug that keeps coming back. resolve the bookmark and
  `startAccessingSecurityScopedResource()` before every play, stop after.
- set `UIFileSharingEnabled` and `LSSupportsOpeningDocumentsInPlace` in Info.plist so files can be
  dropped straight into the apps Documents folder from files.app or a mac.
- register document types / `CFBundleDocumentTypes` broadly (`public.audio`, `public.movie`,
  `public.data`) so "Open in Verse" shows up in the share sheet.
- library persistence is a single `Codable` array written to a json file. not core data, not
  swiftdata, not sqlite. its a personal library bro, it fits in memory.

## 3. lyrics

`Sources/Core/Lyrics.swift` is written, it has the lrc parser and the LRCLIB client. wire it up.

resolution order for a track, first hit wins:
1. sidecar file: same basename, `.lrc` extension, sitting next to the media file.
2. embedded tags: ID3 `SYLT` (synced) or `USLT` (unsynced), vorbis comment `LYRICS`. read thro
   `AVAsset.metadata` where you can.
3. LRCLIB: `GET https://lrclib.net/api/get` with `artist_name`, `track_name`, `album_name`,
   `duration` (seconds, integer). gives back `syncedLyrics` (lrc text) and `plainLyrics`. a 404
   means no match so fall back to `GET /api/search?q=` and take the best duration match. no auth,
   no key. send a real `User-Agent`, LRCLIB asks for one and they run this thing for free.
4. nothing. show plain lyrics if theyre there, otherwise an empty state. do not fake timings, ever.

cache resolved lyrics on disk keyed by the tracks stable id so the car isnt sitting there waiting
on the network.

i also drop `.lrc` files in directly — treat a `.lrc` import as "attach to the track whose basename
matches", and if nothing matches keep it unattached and let me pick.

## 4. youtube

- extraction is **YouTubeKit** (`github.com/alexeichhorn/YouTubeKit`, spm). ask it for streams,
  take highest bitrate audio only for car use, or a muxed/adaptive video stream for the phone.
- ads: extraction pulls the media stream directly so pre roll and mid roll never enter the
  pipeline. theres no ad blocking code to write, it falls out of not using the youtube player.
- **sponsorblock** handles the in video sponsor reads:
  `GET https://sponsor.ajay.app/api/skipSegments?videoID=<id>&category=sponsor&category=selfpromo&category=interaction`
  returns segments as `[[start, end], ...]` in seconds. during playback when position enters a
  segment, seek to its end. thats the whole feature, dont build more.
- input: paste a url, or take a share sheet extension from the youtube app (Info.plist url types +
  a share extension is optional, start with paste).
- extraction fails often and loudly. surface the error. never crash, never sit there showing a
  blank player like nothings wrong.

## 4b. video on the car screen

constraints live in the readme. the implementation is done (`AirPlayVideo.swift`), whats left is ui:

- when the current item passes `canAirPlay`, show `AirPlayButton` on the player screen. tapping it
  lists the cars display *if the head unit supports airplay video in the car* — the system decides
  that, we just show the picker.
- `isExternal` publishes when video moved to the car, so dim the phone surface and show a "playing
  on car display" placeholder.
- parked only enforcement is the systems job. write no speed checks bro.
- do NOT build toward the ios 27 carplay video app entitlement (browse ui on the car). it needs
  apples per app approval and a sideloaded youtube extractor is never getting that.

## 5. carplay — the only genuinely subtle part

`Sources/Core/NowPlaying.swift` is written. it does two things:

**a. standard now playing info.** title, artist, album, duration, elapsed time, playback rate. keep
`MPNowPlayingInfoPropertyElapsedPlaybackTime` accurate on every state change or the cars scrubber
drifts and looks broken. register handlers on `MPRemoteCommandCenter` for play, pause, toggle,
next, previous, changePlaybackPosition, skipForward/Backward.

**b. lyrics rendered into the artwork.** on each lyric line change render a `UIImage` holding the
previous / current / next lines (current one emphasized) and republish `nowPlayingInfo` with a
fresh `MPMediaItemArtwork` around it. the car shows it big, thats the whole point.

rough edges, and you test these in the actual car not the simulator:
- some head units cache artwork hard and wont refresh per line. if mine does, fall back to pushing
  the current lyric line into `MPMediaItemPropertyArtist` or `AlbumTitle` — text fields update
  reliably where images sometimes dont.
- dont republish faster than the lines actually change. lrc lines are seconds apart, thats fine.
  do not run this off a 60Hz display link.
- fall back to real album art the second lyrics arent there.

theres no `CPTemplateApplicationSceneDelegate` in this project. if you catch yourself writing one
you have wandered onto the entitlement path — stop.

## 6. widget, live activity, lock screen

three surfaces, three different capabilities. do not mix them up.

**widget — no video, ever.** a widget is a static swiftui snapshot the system renders ahead of
time. theres no process running while youre looking at it, no render loop, no `AVPlayer`. you
cannot route around this so dont try.

**widget — audio control, yes.** `Sources/Widget/VerseWidget.swift` is written. the intents
conform to **`AudioPlaybackIntent`** not `AppIntent`, and that distinction IS the feature: a plain
widget intent runs inside the widget extension, which has no background audio entitlement and
cannot activate an `AVAudioSession`, so the button would just sit there doing nothing.
`AudioPlaybackIntent` makes the system launch the *app* in the background to perform it, with
audio allowed. if you ever "simplify" these to `AppIntent` the widget silently dies.

left to wire:
- set `PlaybackBridge.shared.player` when the app builds its `Player`.
- call `PlaybackSnapshot.write(...)` on track change and on play/pause. **not per lyric line** —
  widget timeline reloads are budgeted at a few dozen a day and per line reloads get throttled to
  nothing inside one song.
- create the app group `group.com.sol.verse` on both the app and the widget app ids. if the group
  is missing the container url is nil and the widget renders empty with no error at all.

**live activity — this is where per line lyrics go.** activitykit, updated from the app thro
`activity.update()` while background audio keeps the app alive. lands on the lock screen (and the
dynamic island if the device has one). built already — `LyricActivity.swift` has the attributes,
`NowPlaying` starts/updates/ends it (orphan cleanup on launch, foreground resume for the
background start case), and `VerseWidget`s `LyricLiveActivity` renders it. this is the home for
karaoke lyrics outside the car.

**lock screen now playing — already done, free.** `NowPlaying.swift` publishes the lyric artwork
image to `MPNowPlayingInfoCenter` so the lock screen gets the same big synced lyrics the car does.
no extra work.

**carplay does not show third party widgets.** the carplay dashboard belongs to apple, theres no
public api. the now playing screen stays the entire carplay surface.

## verification

non negotiable, because this is a driving app and i cant debug it at 70mph:

- `Tests/LyricsTests.swift`: lrc parser round trip — timestamps `[mm:ss.xx]` and `[mm:ss.xxx]`,
  multiple timestamps on one line, metadata tags (`[ar:]`, `[ti:]`, `[offset:]`), blank lines,
  out of order lines, and `lineIndex(at:)` boundary behavior at 0, exactly on a timestamp, and past
  the last line. use placeholder text, not real lyrics.
- a `demo()` that plays a local file, prints now playing dict transitions, and asserts elapsed time
  tracks position.
- manual: plug into the car. confirm play/pause from the wheel, scrubber accuracy, and whether
  artwork refreshes per line on that specific head unit.

## conventions

- no dependency gets added unless it deletes more code than it costs. the list is final:
  MobileVLCKit, YouTubeKit. everything else is foundation/avfoundation/mediaplayer/swiftui.
- mark deliberate shortcuts with a `TODO(later):` comment naming the ceiling and the upgrade path.
- fewest files that work. do not scaffold for a future that might never show up.
