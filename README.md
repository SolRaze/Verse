# Verse

my media player for iphone (ios 26). sideload only, one user, thats me. plays most formats,
imports youtube / spotify / soundcloud playlists, shows synced lyrics, works on the carplay now
playing screen.

## what it does

- one vlc engine for audio and video — mp3, flac, opus, ogg, ape, mkv, most things
- synced lyrics: sidecar `.lrc` → embedded tags → LRCLIB, cached on disk so car dont wait
- per line lyrics on lock screen as a live activity
- youtube streaming, sponsorblock skips the sponsor parts
- playlist import from youtube, spotify, soundcloud. no api keys
- folder based library — folder tree is the organization. play counts, favourites
- mini player pill, waveform scrubber from real decoded audio, accent colour
- widget + lock screen / carplay controls

## carplay

no entitlement means an audio app only gets the now playing screen. `AVAudioSession(.playback)` +
`MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` give transport, scrubber, metadata, artwork.
thats the whole carplay surface here.

a carplay browse ui needs the `com.apple.developer.carplay-audio` entitlement. apple grants that
per app, so a sideloaded app wont get it. nothing here depends on it.

video on the car screen ("airplay video in the car", ios 26) has three limits, all system
enforced: parked only, car must support the mfi capability (very few do as of mid 2026), and media
must use avplayer external playback. vlc decodes locally so it cant qualify.
`Sources/Core/AirPlayVideo.swift` sends the avplayer compatible stuff (mp4/mov/HLS, extracted
youtube streams count) there. everything else stays on the phone.

in car lyrics: optional setting puts the current line in the artist text field. carplay dont render
live activities, so thats the way around it.

## legal

youtube stream extraction breaks youtubes terms, so no app store. sideload only, personal use.

extraction stops working when youtube rotates its signature cipher, so `YouTubeKit` needs a bump
every few months. it shows an error, it dont crash.

free apple id signing lasts 7 days per install (altstore/sidestore re-sign it). paid developer
program signs for a year.

## building

need a mac with xcode 26+, [xcodegen](https://github.com/yonaskolb/XcodeGen), an apple id (free is
fine), an iphone on ios 26+.

```sh
brew install xcodegen
git clone https://github.com/SolRaze/Verse && cd Verse
xcodegen generate     # writes Verse.xcodeproj; SPM pulls VLCKit + YouTubeKit on first build
open Verse.xcodeproj
```

team + bundle id go in `project.yml`, or change signing in xcode after generating. run from xcode
with a phone selected, or cli:

```sh
xcodebuild -scheme Verse -destination 'platform=iOS,id=<device-udid>' \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <device-udid> \
  ~/Library/Developer/Xcode/DerivedData/Verse-*/Build/Products/Debug-iphoneos/Verse.app
```

`xcrun devicectl list devices` gives the udid. dependencies are pure spm. no cocoapods, no
workspace.

## where stuff is

| File | What it is |
|---|---|
| `Sources/Core/Player.swift` | VLCKit engine — every format, audio and video. |
| `Sources/Core/NowPlaying.swift` | CarPlay / lock-screen surface + Live Activity lyrics. |
| `Sources/Core/Lyrics.swift` | LRC parser + LRCLIB client + embedded-tag fallback. |
| `Sources/Core/AirPlayVideo.swift` | AVPlayer path — the only route video takes to the car screen. |
| `SPEC.md` | full brief, read it first. |
