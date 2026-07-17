# Backlog — features

Wanted, not built. Bugs live in `ISSUES.md`. Source: `verse-inbox.md` (2026-07-16).
Design north star: Apple's own apps (Music, Files) — take inspiration from their philosophy.

---

## Navigation: Home / Library tabs — **SHIPPED** (2026-07-17)

- ~~Move today's single screen into a **Library** tab.~~
- ~~New **Home** tab: big `Music` title, search bar beneath, playlists, most-played albums,
  most-played tracks.~~ `Sources/App/HomeView.swift`.
- ~~Bottom tab bar for Home + Library~~ — `Sources/App/RootView.swift`, which also owns the
  mini player and the player sheet so they survive tab switches and navigation.
- ~~Fold the options/burger menu into `+`, change that icon to **three dots**.~~ One
  `ellipsis.circle` menu on the Library tab.
- Play-count tracking landed with it: `playCount` / `lastPlayed` on `LibraryItem`, counted in
  `Coordinator.start`. This is the data Wrapped needs too.

"Album" is a folder that directly holds tracks — this library has no album tag, and the folder
tree is the organization. Revisit if real album metadata ever appears.

Still open here: more tabs (Locations, per Jellyfin below).

## Now Playing redesign

- **Minimize chevron** instead of the drag bar; remove the bar entirely.
- Album art **top-center**, **square corners** (drop the rounding), offset a bit further down.
- **Burger menu, top right**: song description/info, like, share, view track, view artist.
- Move the **AirPlay icon to the bottom**.
- **Glass/translucent play button**.

## Mini player — **SHIPPED** (2026-07-17)

- ~~More **capsule**-shaped, same translucent material.~~
- ~~**Play button on the left**; cast/AirPlay also left.~~
- ~~**Swipe for next / previous**.~~ The forward button is gone; the swipe replaces it.
- Sits in `.tabViewBottomAccessory` (iOS 26) rather than a hand-rolled `safeAreaInset`, so it
  rides above the tab bar's glass pill instead of sitting flush under it. That container draws
  its own capsule and material — don't add a background inside it or you nest two capsules.

## App icon — **SHIPPED** (2026-07-17)

- ~~Replace with something new — a **CD or vinyl**.~~ CD: flat disc with an iridescent sheen, a
  square hole punched through its right rim, on a near-black plate. Vinyl was drawn first and
  dropped.
- **The sheen is a sanctioned exception to the no-gradient rule, and it is icon-only.** That rule
  governs UI chrome (`.tint(.white)`, no colored chrome) and still holds everywhere else — a CD
  without its sheen is just an anonymous disc. Do not "fix" this icon by flattening it.
- The square straddles the rim by choice. It eats part of the silhouette, so the disc reads a
  little like a "C" — that was reviewed and kept.
- Regenerate with `Tools/makeicon.swift` (not in any target; see the header for the command).
  Knobs: `SQ` (square size), `SQX` (its distance from centre; 360 = on the rim), `FLAT=1` for the
  monotone no-sheen disc, and `vinyl` as the style argument for the old one.

## Likes / favorites

Implied by the Now Playing "like" action: needs a favorite flag on `LibraryItem` and
somewhere to browse it.

## Jellyfin servers

- Connect to **Jellyfin** servers.
- Files-app-style **Locations** tab: browse and connect to a server alongside local folders.

## Wrapped — year-end listening recap

- Track plays over time (the data "most played" needs too).
- **Spotify-Wrapped-like** recap, shown at year end on the same date Spotify uses
  (~December 22), matching their tracking window.
