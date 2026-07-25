# Verse

my media player for iphone (ios 26) bro. sideload only, single user, and that user is me. plays
every format, imports youtube / spotify / soundcloud playlists, shows synced lyrics, and lands on
the carplay now playing screen. apple music does less than this and takes your money for it.

## what it does

- one vlc engine for all audio and video — mp3, flac, opus, ogg, ape, mkv, whatever you throw at it
- synced lyrics: sidecar `.lrc` → embedded tags → LRCLIB, cached on disk so the car never waits
- per line lyrics on the lock screen as a live activity, karaoke in your pocket
- youtube streaming with sponsorblock skipping the sponsor reads for you
- playlist import from youtube, spotify and soundcloud, no api keys, no accounts, nothing
- folder based library — the folder tree IS the organization, plus play counts and favourites
- mini player pill, waveform scrubber drawn from real decoded audio not a fake bar, full range
  accent colour
- widget + lock screen / carplay transport controls

## carplay, read this before you argue with me

- with no entitlement an audio app reaches carplay ONLY thro the now playing screen:
  `AVAudioSession(.playback)` + `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` give you
  transport, scrubber, metadata and artwork. thats the entire carplay surface, thats it, dont go
  looking for more.
- a carplay browse ui needs the `com.apple.developer.carplay-audio` entitlement and apple hands
  that out per app like its gold. never happening for a sideloaded app so nothing here depends on
  it and nothing here should be built toward it.
- video on the car screen ("airplay video in the car", ios 26) has three constraints the system
  enforces, not me: parked only, the car has to support the mfi capability (basically none do as
  of mid 2026), and the media has to use avplayer external playback — vlc decodes locally so it
  cannot qualify, ever. `Sources/Core/AirPlayVideo.swift` routes the avplayer compatible stuff
  (mp4/mov/HLS, extracted youtube streams count) over there, everything else stays on the phone.
- in car lyrics: theres an optional setting that shoves the current line into the artist text
  field. carplay does not render live activities, so thats the workaround and it works.

## legal, or whatever

- youtube stream extraction breaks youtubes terms of service, so app store distribution is
  impossible. sideload only, personal use, i dont care.
- extraction breaks every time youtube rotates its signature cipher — `YouTubeKit` needs a bump
  every few months. when it fails it shows a visible error, it does not crash.
- free apple id signing dies after 7 days per install (altstore/sidestore re-sign it for you), the
  paid developer program signs for a year.

## building it

you need a mac with xcode 26+, [xcodegen](https://github.com/yonaskolb/XcodeGen), an apple id
(free one works fine), and an iphone on ios 26+.

```sh
brew install xcodegen
git clone https://github.com/SolRaze/Verse && cd Verse
xcodegen generate     # writes Verse.xcodeproj; SPM pulls VLCKit + YouTubeKit on first build
open Verse.xcodeproj
```

team + bundle id go in `project.yml`, or just change signing in xcode after generating. run it
from xcode with a phone selected, or from the cli:

```sh
xcodebuild -scheme Verse -destination 'platform=iOS,id=<device-udid>' \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <device-udid> \
  ~/Library/Developer/Xcode/DerivedData/Verse-*/Build/Products/Debug-iphoneos/Verse.app
```

`xcrun devicectl list devices` gives you the udid. dependencies are pure spm — no cocoapods, no
workspace, none of that mess.

## where stuff is

| File | What it is |
|---|---|
| `Sources/Core/Player.swift` | VLCKit engine — every format, audio and video. |
| `Sources/Core/NowPlaying.swift` | CarPlay / lock-screen surface + Live Activity lyrics. |
| `Sources/Core/Lyrics.swift` | LRC parser + LRCLIB client + embedded-tag fallback. |
| `Sources/Core/AirPlayVideo.swift` | AVPlayer path — the only route video takes to the car screen. |
| `SPEC.md` | the full brief, read it before touching anything. |
