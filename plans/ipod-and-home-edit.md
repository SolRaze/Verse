# Plan — iPod Mode & Home edit gesture

Status: proposed (2026-07-21). Not started. Written against `IPodView.swift`
(current skeleton) and `HomeView.swift`.

## A. iPod Mode — from skeleton to usable

`IPodView.swift` today: a static click-wheel face. MENU dismisses, the side
buttons skip, centre toggles play/pause. No rotary input, no menu tree, no
library browsing. Repos to mine: keremersu35/iPodPlayer (UI/rotary),
lukew3/stemPlayerOnline (interaction feel).

Ordered, each shippable on its own:

1. **Rotary scroll on the wheel.** A `DragGesture` on the wheel ring, angle
   delta → selection index. Compute angle from touch point vs wheel centre;
   accumulate crossings of ~30° into one "tick" (haptic per tick). This is the
   headline feature — without it the wheel is decoration.
2. **Menu tree.** A `Screen` enum (`.main`, `.songs`, `.albums`, `.artists`,
   `.nowPlaying`) with a navigation stack the wheel scrolls and the centre
   button selects; MENU pops one level (not straight to dismiss). Reuse
   `library.items` / `mostPlayedAlbums()` for data — no new store.
3. **Now Playing screen** with the wheel as a scrubber (rotate = seek) and a
   cover thumbnail; ties to `coordinator.player` position/duration already
   published.
4. **Cover-flow albums** (optional, later): horizontal album art the wheel
   flips through. Cosmetic; do last.

Constraints: keep it one file if it stays under ~300 lines; split only when the
menu tree grows. No new persistence — iPod Mode is a *view* over the existing
library/coordinator, never its own model. Playback always routes through
`coordinator` so lock screen / CarPlay / Live Activity stay in sync.

Escape hatch: if rotary math fights SwiftUI hit-testing, fall back to a UIKit
`UIPanGestureRecognizer` on a representable wheel view (same superview-attach
trick that the removed DeepPress used) rather than forcing SwiftUI gestures.

## B. Home edit — gesture without a button

The visible **Edit** button (top-right of Home) is the current, reliable way in.
The earlier firm-press / 3-finger gestures were removed because they fought the
tiles' own taps (tiles stopped responding). A non-blocking re-add:

- Attach a `UILongPressGestureRecognizer` (min duration ~0.6s) to the Home
  scroll view's **superview** with `cancelsTouchesInView = false` and a
  delegate returning `shouldRecognizeSimultaneouslyWith = true`, so taps and
  scrolls pass through untouched and only a deliberate long-press on empty space
  toggles edit. Verify on device that album/track taps still fire *before*
  removing the Edit button.
- Keep the Edit button regardless — discoverability. The gesture is a shortcut,
  not the only door.

Done criteria: with the gesture live, every Home tile still navigates/plays on a
single tap (the regression that pulled the last attempt), and a long-press on
blank Home area toggles edit mode.
