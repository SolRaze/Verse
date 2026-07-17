# Verse inbox

Notes stay here permanently. Each gets a status line as it's triaged or built.
Legend: **DONE** = shipped · **PARTIAL** = some of it shipped · **ISSUE** = tracked in
`ISSUES.md` · **BACKLOG** = tracked in `BACKLOG.md`.
Last triage: 2026-07-16.

---

the music playback and its recalling feature takes time to load content, change the icon to something new like a cd or vinyl, use the apple design philosophy and get inspiration form their apps:

> - slow load → **ISSUE #4** (suspects: LRCLIB lookup before play, YouTube re-extraction, artwork backfill)
>   — 2026-07-17: root cause confirmed on #4. Play start awaits lyrics + artwork before
>   `player.load`, and neither caches a miss, so a track with no lyrics re-hits LRCLIB every play.
> - cd/vinyl icon → **DONE** (2026-07-17). CD after `reference.jpg` (Yeezus cover): dark disc,
>   iridescence through the left/right sectors, near-black top and bottom, soft radial streaks,
>   solid red tape square across the right rim. Vinyl drawn first and dropped.
>   The sheen and the red square are sanctioned **icon-only** exceptions to the no-gradient /
>   monotone rules — those govern UI chrome and still hold everywhere else.
>   `Tools/makeicon.swift` regenerates it (knobs: `SQ`, `SQX`, `SPOKES`, `FLAT=1`, style `vinyl`).
> - Apple design philosophy → **BACKLOG** (noted as the north star)

**now playing** move a minimize arrow instead of bat display album on top in the center and remove that bar, and add burger menu on right with song description info, like and share and view track and view artist, disable rounded corners on album art, move it from even slightly more, move the airplay icon to bottom and add the glass transparency to the play button, also in mini player make it a bit **capsule** like with play button on left with same ui transparency  and swipe for next music and previous, and cast / airplay to the left

> **PARTIAL** — done: album art is top-center, and offset further down (44pt) so it clears the
> handle. Also shipped alongside: art no longer zoom-crops, Lyrics button, shuffle + repeat.
> 2026-07-17: the whole **mini player** half is done — capsule, play button left, cast/AirPlay
> left, swipe for next/previous (the forward button is gone), and it now sits above the tab pill
> in `.tabViewBottomAccessory`.
> Still open → **BACKLOG** (Now Playing redesign): minimize arrow replacing the drag bar, burger
> menu (info / like / share / view track / view artist), square art corners, AirPlay moved to
> bottom, glass play button.

on homepage move the current layout to the library tab and make a new **home** tab with Music title and display a playlists, most played albums and most played music, make burger menu part of + and chance icon to three dots, Add a big title Music like the files app on iPhone beneath it he search bar and a then imports and playlist a well organized and smart system, and below pages for home library and suggest more

> **DONE** (2026-07-17) — Home + Library tabs shipped. `HomeView` has the big Music title, search
> beneath it, playlists, most-played albums and most-played tracks; the burger menu is folded into
> one three-dots menu on Library. Unblocked by adding play-count tracking (`playCount` /
> `lastPlayed` on `LibraryItem`, counted in `Coordinator.start`) — the same data Wrapped needs.
> "Album" = a folder that directly holds tracks; this library has no album tag.
> Still **BACKLOG**: "imports" as its own Home shelf, and more tabs (Locations).

adding **soundcloud** and **spotify** playlist link gives error title "**something failed**" description "Soundcloud / Spotify gave a page this app no longer understands - the scraper needs updating." submit "**ok**".

> **ISSUE #1** — not a dead scraper: the device tests for a Spotify editorial playlist and a
> SoundCloud `/sets/` link both pass. It's a coverage gap — Spotify handles only `/playlist/`
> (no `spotify.link` short URLs, albums, tracks), SoundCloud only `/sets/`.

**youtube** playlist importing works but only displays 100 maximum if number over hundred, video playback disabled currently when playing.

> - 100 cap → **ISSUE #2** (first innertube page only; continuation tokens not followed)
> - video playback disabled → **ISSUE #3**, needs clarification. Playlist entries are routed
>   audio-only through VLC by design, so video never shows for them — is that what you hit?

in future add a function to connect to **Jellyfin** servers and like in the files app display a location tab and connect to server, make a **Spotify wrapped** like system for tracking and display on the end of year like the exact date December 22 or same day that Spotify displays with its tracking date same as showing.

> **BACKLOG** (Jellyfin servers, Wrapped).



when inside the folder retain the mini player location or position 

> **DONE** (2026-07-17) — was untriaged. The mini player was re-declared as a bottom
> `safeAreaInset` on every screen (Library, FolderView, PlaylistDetailView), so it was laid out
> fresh per push. It now lives once on the tab shell (`RootView`), above the tab bar, so it stays
> put across navigation and tab switches.


---

## Shipped since this inbox was written

- Album art top-center with a 44pt offset; `scaledToFit` so covers no longer zoom-crop.
- Dedicated Lyrics button; synced lyrics overlaid on the artwork.
- Shuffle (keeps current track, restores order) and repeat off → all → one.
- Swipe-back fixes attempted twice — still open, tracked as **ISSUE #5**.

