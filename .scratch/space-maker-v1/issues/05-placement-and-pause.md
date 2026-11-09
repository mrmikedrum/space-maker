# 05: Placement and pause

**What to build:** A window that matches an Assignment is restored to its Space the moment it appears. The menu bar has a pause/resume toggle for automatic behaviour.

The headline demo: the user quits Chrome and relaunches it, and every tracked Chrome window returns to its Space without any action from the user.

**Blocked by:** 04

**Status:** ready-for-agent

- [x] Engine tests against the fake cover: a Chrome relaunch that drops every window on the current desktop ends with each window on its Space; a window with no Assignment that appears is left alone; nothing moves while paused; behaviour resumes after resume.
- [x] Placement never fights the user. A window the user moves after it was placed is not moved back automatically.
- [ ] Demo on the real Mac: quit and relaunch Chrome. All tracked windows go home. (Pending live demo.)

## Comments

- Built test-first against the fake `WindowSystem` (`PlacementTests`, 5 tests; 61 total). The port gains a `windowAppeared` event; the fake's `relaunchChrome` now brings windows back one at a time, each announcing itself.
- **Placement** (`Engine/Placement.swift`): a window that appears is Restored alone if it matches an Assignment, isn't Ignored or fullscreen, and moves aren't Doctor-disabled. A failed move is Soft Drift, like Restore. Each window gets one chance in its life (`appearedWindows`, cleared on close), so a window the user moves after placement, or one that appeared while paused, is never moved back automatically; it shows as Drift instead. A window macOS doesn't list yet can be announced again later.
- **Pause:** `pause`/`resume` commands (engine, MCP, menu bar toggle); `status` reports `isPaused`; the menu icon's tooltip says so. In memory only: Space Maker starts unpaused. Ticket 08 should check `Engine.isPaused` before any automatic Restore.
- **Adapter** (`MacOS/WindowAppearanceObserver.swift`): an `AXObserver` per regular app for `kAXWindowCreatedNotification` (announced after 0.5 s so SkyLight lists the window), plus sweeps of a newly launched app's windows at 1/3/6 s, since Chrome can restore windows before its observer exists. Observers are added lazily on launch/activation, so a later Accessibility grant is picked up. Pending live demo.
- The menu bar now refreshes on every port event (`Engine.onChange`), but keeps the 5 s Drift poll: there is still no event for a window the user moves between desktops.

