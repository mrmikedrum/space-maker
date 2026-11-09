# 09: Saved positions per Display Setup

**What to build:** Save also records each window's position and size for the current Display Setup only, relative to the display it's on. Restore and Placement apply the saved position when one exists for the current Display Setup. Otherwise they enforce only the Space. The user never types a number. A window on the right Space but away from its saved position for the current Display Setup counts as Drift.

**Blocked by:** 07

**Status:** ready-for-agent

- [x] Engine tests against the fake cover: a Save while docked leaves laptop positions untouched; Restore applies the right Display Setup's frame; windows without a saved frame keep their size and position; frames survive a resolution change because they are display-relative.
- [x] Engine tests cover a window on the right Space but at the wrong position being reported as Drift, and one without a saved position for this Display Setup not being reported.
- [ ] Demo: arrange a window, Save, move and resize it, then Restore. It snaps back. (pending live demo)

## Comments

- Built test-first against the fake `WindowSystem` with a real Layout in a temp folder (`SavedPositionTests`, 12 tests): Save while docked leaves laptop positions alone; Restore applies the current Display Setup's frame; no saved frame keeps size and position; a resolution change scales the frame; Position Drift (with a 2-point tolerance) and no Drift without a saved frame for this Display Setup; per-window Save keeps the new position; a refused resize is Soft Drift, not retried until the world changes; Layout contents; Placement (ticket 05) applies the saved frame too.
- Port: displays gain `visibleFrame`, windows `frame` (screen points, top-left origin), and a `setFrame` action. The macOS adapter reads `NSScreen.visibleFrame` (flipped) and `kCGWindowBounds`, and sets frames through Accessibility (size, position, size). No private API added.
- Layout: each Assignment gains optional `frames` (`displaySetup` key + `frame` as fractions of the display's visible frame, so it survives resolution changes). Omitted when empty; older Layouts load unchanged; version stays 1.
- Drift gains kind `position`; the menu bar shows it as "Out of place" with Restore/Save/Ignore.
- Live risk for the demo: Accessibility only reaches windows on desktops currently showing, so Restore may fail to set the frame of a window it just moved to a hidden desktop. That shows as Soft Drift with a "switch to it and Restore" hint. Real-Mac demo pending live demo (user away).
