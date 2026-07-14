# Roadie

Personal media player for iPhone (17e, iOS 26). Sideload-only. Plays anything, shows synced
lyrics, streams YouTube ad-free, and puts all of it on the CarPlay Now Playing screen.

## Read this before you write any code

**CarPlay video exists since iOS 26, with three hard constraints.** "AirPlay video in the car"
lets any app that supports AirPlay video streaming play video on the CarPlay display. The
constraints, all enforced by the system: (1) **parked only** — driving stops playback; (2) the
**car must support the feature** (an MFi capability automakers opt into — factory support is
still nearly nonexistent as of mid-2026); (3) the media must go through **AVPlayer external
playback** — VLC decodes locally and can never AirPlay video. `Sources/Core/AirPlayVideo.swift`
is that path: AVPlayer-compatible content (mp4/mov/HLS, incl. every extracted YouTube stream)
routes there so the AirPlay picker can offer the car; everything else stays on VLC, phone only.

iOS 27 adds a proper CarPlay **video app entitlement** (browse UI on the car screen, parked
playback). It requires Apple approving your app — plausible for Netflix, not for a sideloaded
personal YouTube player. File at https://developer.apple.com/contact/carplay/ if you want to try;
build nothing that depends on it.

**CarPlay browse UI for audio also needs an entitlement** (`com.apple.developer.carplay-audio`),
same approval path. Assume it is not coming.

**If the car doesn't support AirPlay video in the car** (today: almost all of them), no app code
helps. The working fallbacks are hardware: an Android "AI box" in the CarPlay USB port, or an
aftermarket head unit that supports the feature.

**What works with no entitlement at all:** any iOS app that plays audio, configures
`AVAudioSession(.playback)`, and populates `MPNowPlayingInfoCenter` + `MPRemoteCommandCenter`
appears on the CarPlay Now Playing screen automatically. Transport controls, scrubber, metadata,
and artwork all work. That is the entire CarPlay surface for this project, and it is enough.

**The lyrics trick:** CarPlay renders the now-playing artwork large. Roadie renders the current
synced-lyric window (previous / current / next lines) into a `UIImage` and publishes that as
`MPMediaItemArtwork`, refreshed on each line change. Result: big synced lyrics on the car screen
with zero entitlements. See `Sources/Core/NowPlaying.swift`.

## Legal / distribution

- YouTube stream extraction violates YouTube's Terms of Service. App Store rejection is certain.
  This is a sideload-only personal build. Ship it to yourself, nobody else.
- Extraction breaks whenever YouTube rotates its signature cipher. Expect to bump `YouTubeKit`
  every few months. Build the UI so a failed extraction is a visible error, not a crash.
- Sideload lifetime: free Apple ID = 7-day provisioning, needs re-signing (use AltStore/SideStore
  to automate). Paid Developer Program ($99/yr) = 1-year provisioning, far less friction.

## Setup

```sh
brew install xcodegen cocoapods
cd ~/Projects/Roadie
xcodegen generate
pod install
open Roadie.xcworkspace
```

Set your team + bundle id in `project.yml` before generating.

## Where the real work is

| File | Why it matters |
|---|---|
| `Sources/Core/NowPlaying.swift` | The CarPlay surface. Lyric-into-artwork renderer. |
| `Sources/Core/Lyrics.swift` | LRC parser + LRCLIB client + embedded-tag fallback. |
| `Sources/Core/Player.swift` | VLCKit engine. Plays every format, audio and video. |
| `Sources/Core/AirPlayVideo.swift` | AVPlayer path — the only way video reaches the car screen. |
| `SPEC.md` | Full build brief. Hand this to the agent. |
