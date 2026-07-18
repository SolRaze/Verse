# Verse inbox

Notes stay here permanently. Each gets a status line as it's triaged or built.
Legend: **DONE** = shipped · **PARTIAL** = some of it shipped · **ISSUE** = tracked in
`ISSUES.md` · **BACKLOG** = tracked in `BACKLOG.md`.
Last triage: 2026-07-18.

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



bro using too many colors on icon reduce that and add more depth on the darker tone(increase values)

> **DONE** (2026-07-18) — sheen cut to two hues (green/violet), tonal steps 4 → 5, dark floor
> deepened (brightness 0.18 → 0.12, hub to match). New defaults in `Tools/makeicon.swift`
> (`HUES`/`LEVELS` env knobs still override). Red tape also narrowed to the reference's 1.22
> tall ratio the same day.

make the library layout same as the homepage with big label on top and remove search bar from home and add it to new page as a dock button

> **DONE** (2026-07-18) — Library gets a big "Library" title like Home. Home's search bar is
> gone; search is now its own dock pill (`Tab(role: .search)`, Files-app style) opening a
> dedicated Search page. Library keeps its local search for filtering while browsing.

make mini player pill like apple music album on left and the play and forward button on right with removing swipe feature to forward and back, 

> **DONE** (2026-07-18) — album art (or thumbnail) left, title middle, play + forward right,
> swipe gesture removed. AirPlay left the mini player; it lives in the full player.

new feature add to queue and a sub context menu on hold, 

> **DONE** (2026-07-18) — hold a track → "Add to Queue" submenu with Play Next / Play Last
> (`Coordinator.playNext/playLast`). With nothing playing, either just plays the track.
> Enqueued items don't survive a shuffle toggle (shuffle restores the pre-shuffle queue) —
> acceptable for now.

also inside folders the distance between mini player looks off a straight cuts off so make it apper behind mini player and end not reacting the buttons, 

> **BELIEVED FIXED** (2026-07-18) — the hard cut-off was the old per-screen `safeAreaInset`
> bar. The bar now sits in the system's `.tabViewBottomAccessory` slot and folder lists are
> plain `List`s, so content scrolls behind it with system insets. Confirm on device.

the dock button functions weird as it is small when song played it grows in size make it constant, 

> **BELIEVED FIXED** (2026-07-18) — the "small" state was an empty glass capsule the accessory
> rendered with nothing playing; it then "grew" when a song filled it. The accessory now only
> exists while something plays, so there's no small state. Confirm on device.

inside current playing fullscreen take inspiration from above but newer recommendations here if overlapping from above idea take this as standard, 

> **PARTIAL** (2026-07-18) — Now Playing redesign shipped: minimize chevron replaces the drag
> capsule, burger menu top right (Info / Like / Share — Like is a new persisted `liked` flag),
> square art corners, AirPlay moved to the bottom under the transport, glass play button
> (`glassEffect`). Still open → **BACKLOG**: "View Track" / "View Artist" menu items (need
> deep-links from the sheet into the Library stack).

while inside lyrics button the mini player stays and the now playing song's wav data or the frequency range displays on the bar without any button and just the scrubber, check the way the files app play sound filed inside app for reference and keep their measurements as standard with same ui a close button on top right, and a play button on bottom left and a queue button on the bottom right 

> **PARTIAL** (2026-07-18) — Lyrics is now a fullscreen page: close top right, track pill that
> stays put, bare scrubber (no transport on it), play bottom left, queue bottom right (opens an
> Up Next sheet). Still open → **BACKLOG**: waveform/frequency drawn on the scrubber — VLC
> exposes no decoded samples, needs a separate decode pass (`ponytail:` comment marks the spot).


---

## Shipped since this inbox was written

- Album art top-center with a 44pt offset; `scaledToFit` so covers no longer zoom-crop.
- Dedicated Lyrics button; synced lyrics overlaid on the artwork.
- Shuffle (keeps current track, restores order) and repeat off → all → one.
- Swipe-back fixes attempted twice — still open, tracked as **ISSUE #5**.
  2026-07-18: verified fixed — the `SwipeBackTests` UI test (one edge swipe pops a folder)
  now passes on the iOS 26.5 simulator.

