# Roadie

Personal media player for iPhone (17e, iOS 26). Sideload-only. Plays anything, shows synced
lyrics, streams YouTube ad-free, and puts all of it on the CarPlay Now Playing screen.

## Read this before you write any code

**CarPlay video is impossible.** Apple gates CarPlay to a fixed set of app categories (audio,
communication, navigation, EV charging, parking, quick food, fueling, driving task). There is no
video category and no public API to draw video on the CarPlay display. The only routes are a
jailbreak (none exists for A19 / iOS 26) or Apple granting you an entitlement they do not grant
for this. Do not spend time here.

**CarPlay browse UI also needs an entitlement** (`com.apple.developer.carplay-audio`). Apple must
enable it on your App ID after you file https://developer.apple.com/contact/carplay/ . Assume it
is not coming.

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
| `Sources/Core/Player.swift` | Single VLCKit engine. Plays every format, audio and video. |
| `SPEC.md` | Full build brief. Hand this to the agent. |
