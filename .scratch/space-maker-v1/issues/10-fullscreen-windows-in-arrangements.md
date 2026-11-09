# 10: Fullscreen windows in Arrangements

**What to build:** Save records fullscreen windows as items in the Arrangement, interleaved with Spaces in on-screen order, e.g. "Game fullscreen, Tasks, Personal, Work, Work fullscreen".

Restore leaves a fullscreen window alone if it's fullscreen on the right display. Otherwise it exits fullscreen, moves the window to the desktop just before its place, and re-enters fullscreen.

If a window is on the right display but in the wrong order (including one that should come before a display's first desktop), that is Soft Drift with a "drag it in Mission Control" hint.

**Blocked by:** 07, 06

**Status:** ready-for-agent

- [x] Engine tests against the fake cover: undock and redock end with Work main and Game main fullscreen on the right display; a window already correct is never re-fullscreened; an order the fake can't achieve becomes Soft Drift; Restore doesn't loop.
- [ ] Demo on the real Mac: take Game main out of fullscreen, then Restore all. It goes back to fullscreen on the laptop display. (pending live demo)

## Comments

- Built test-first against the fake `WindowSystem` with a real Layout in a temp folder (`FullscreenTests`, 8 tests). The port gains `setFullscreen(_:_:)`; the fake makes a fullscreen desktop just after the window's desktop on entry, and puts the window on the regular desktop before on exit. The fake's undock now collapses into the laptop's first *regular* desktop.
- Layout: each display's Arrangement gains `fullscreenWindows` (`name`, `spacesBefore`), left out when empty, so older Layouts load and unchanged ones are written identically; version stays 1. A fullscreen window's Assignment names its place (e.g. "Work fullscreen", from the Chrome profile or app name) in its `space` field. Save keeps an existing place name on re-save.
- Restore: fullscreen on the right display is left alone, even in the wrong order (Soft Drift, "drag it in Mission Control"). Otherwise exit fullscreen, move to the regular desktop just before its place (the first desktop for a place before the first Space, which lands one late → Soft Drift), re-enter. A failed step is Soft Drift and not retried until the world changes.
- Matching: a fullscreen Assignment whose window left fullscreen takes the one otherwise-matching unmatched window, so "take Game main out of fullscreen, Restore" works. Unassigned fullscreen windows are now `new` Drift. Limitation: an unnamed Work main that leaves fullscreen alongside an unnamed Work second can be mistaken for Work second.
- Adapter: sets `AXFullScreen` and polls SkyLight until the window is on a desktop of the right kind (3 s timeout). Accessibility can't reach windows on hidden desktops, so those become Soft Drift. Real-Mac demo pending live demo (user away).
- `save` by handle and `move_window` still refuse fullscreen windows, now with a reason instead of "yet".
- After merging 09: fullscreen windows get no saved position (they fill the display); Placement (05) still skips fullscreen windows, since Chrome restores them to fullscreen itself.
