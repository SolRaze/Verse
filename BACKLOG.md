# Backlog — features

Wanted, not built. Bugs live in `ISSUES.md`. Source: `verse-inbox.md` (2026-07-16).
Design north star: Apple's own apps (Music, Files) — take inspiration from their philosophy.

---

## Navigation: Home / Library tabs

- Move today's single screen into a **Library** tab.
- New **Home** tab: big `Music` title (Files-app style), search bar beneath it, then
  playlists, most-played albums, most-played tracks — a well-organized, "smart" landing page.
- Bottom tab bar for Home + Library; room to suggest more tabs later.
- Fold the options/burger menu into `+`, change that icon to **three dots**.

Needs play-count tracking (see Wrapped below) before "most played" is real.

## Now Playing redesign

- **Minimize chevron** instead of the drag bar; remove the bar entirely.
- Album art **top-center**, **square corners** (drop the rounding), offset a bit further down.
- **Burger menu, top right**: song description/info, like, share, view track, view artist.
- Move the **AirPlay icon to the bottom**.
- **Glass/translucent play button**.

## Mini player

- More **capsule**-shaped, same translucent material.
- **Play button on the left**; cast/AirPlay also left.
- **Swipe for next / previous**.

## App icon

- Replace with something new — a **CD or vinyl**.

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
