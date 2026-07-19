# Verse

Personal media player for iPhone (iOS 26). Sideload-only, single-user. Plays every format,
imports YouTube / Spotify / SoundCloud playlists, shows synced lyrics, and lands on the
CarPlay Now Playing screen.

## Features

- One VLC engine for all audio and video — mp3, flac, opus, ogg, ape, mkv, anything
- Synced lyrics: sidecar `.lrc` → embedded tags → LRCLIB, cached on disk
- Per-line lyrics as a Lock Screen Live Activity
- YouTube streaming with SponsorBlock segment skipping
- Playlist import from YouTube, Spotify and SoundCloud — no API keys
- Folder-based library (the folder tree is the organization), play counts, favourites
- Mini player pill, waveform scrubber drawn from decoded audio, full-range accent colour
- Widget + lock screen / CarPlay transport controls

## CarPlay

- With no entitlement, an audio app reaches CarPlay only via the Now Playing screen:
  `AVAudioSession(.playback)` + `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter` provide
  transport, scrubber, metadata and artwork. That is Verse's entire CarPlay surface.
- A CarPlay browse UI requires the `com.apple.developer.carplay-audio` entitlement, granted
  per-app by Apple. Out of reach for a sideloaded app; nothing here depends on it.
- Video on the car screen ("AirPlay video in the car", iOS 26) has three system-enforced
  constraints: parked only, the car must support the MFi capability (nearly none do as of
  mid-2026), and the media must use AVPlayer external playback — VLC decodes locally and
  cannot qualify. `Sources/Core/AirPlayVideo.swift` routes AVPlayer-compatible content
  (mp4/mov/HLS, including extracted YouTube streams) there; everything else stays on the phone.
- In-car lyrics: an optional setting shows the current line in the artist text field. CarPlay
  does not render Live Activities.

## Legal / distribution

- YouTube stream extraction violates YouTube's Terms of Service; App Store distribution is
  impossible. Sideload-only, personal use.
- Extraction breaks whenever YouTube rotates its signature cipher — `YouTubeKit` needs a bump
  every few months. Failed extraction surfaces as a visible error, not a crash.
- Free Apple ID signing lasts 7 days per install (AltStore/SideStore automate re-signing);
  the paid Developer Program signs for a year.

## Building

Requirements: Mac with Xcode 26+, [xcodegen](https://github.com/yonaskolb/XcodeGen), an
Apple ID (free works), an iPhone on iOS 26+.

```sh
brew install xcodegen
git clone https://github.com/SolRaze/Verse && cd Verse
xcodegen generate     # writes Verse.xcodeproj; SPM pulls VLCKit + YouTubeKit on first build
open Verse.xcodeproj
```

Team + bundle id belong in `project.yml` (or change signing in Xcode after generating).
Run from Xcode with a phone selected, or from the CLI:

```sh
xcodebuild -scheme Verse -destination 'platform=iOS,id=<device-udid>' \
  -allowProvisioningUpdates build
xcrun devicectl device install app --device <device-udid> \
  ~/Library/Developer/Xcode/DerivedData/Verse-*/Build/Products/Debug-iphoneos/Verse.app
```

`xcrun devicectl list devices` prints the udid. Dependencies are pure SPM — no CocoaPods,
no workspace.

## Layout

| File | What it is |
|---|---|
| `Sources/Core/Player.swift` | VLCKit engine — every format, audio and video. |
| `Sources/Core/NowPlaying.swift` | CarPlay / lock-screen surface + Live Activity lyrics. |
| `Sources/Core/Lyrics.swift` | LRC parser + LRCLIB client + embedded-tag fallback. |
| `Sources/Core/AirPlayVideo.swift` | AVPlayer path — the only route video takes to the car screen. |
| `SPEC.md` | Full project brief. |
