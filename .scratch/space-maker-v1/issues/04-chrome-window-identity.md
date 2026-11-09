# 04: Chrome window identity

**What to build:** The user's Chrome windows (Work main fullscreen, Work second, Game main fullscreen, Personal main) each get their own stable Assignment.

Windows are matched by app, Chrome profile and whether they're fullscreen. A name is used only as a tiebreaker.

When those keys are ambiguous, Save names the Chrome window automatically through Chrome's scripting interface. The name survives a Chrome relaunch.

`name_window` on MCP lets the user or an agent set a meaningful name. Unnamed windows that have closed are dropped on the next Save. Named windows stay in the Layout.

**Blocked by:** 03

**Status:** ready-for-agent

- [x] Engine tests against the fake cover: two same-profile normal windows get auto-named on Save; a relaunch with fresh handles still matches every window; profile plus the fullscreen flag tells windows apart without any name; named and unnamed windows are pruned correctly.
- [x] Save requests Automation permission for Chrome. If it's denied, auto-naming is skipped, Save still succeeds, and a Doctor finding records why. (Engine side tested against the fake; the real prompt and the "Chrome Automation" Doctor check are pending live demo.)
- [x] Apps other than Chrome fall back to matching on app plus title.
- [ ] Demo: `status` on the real Mac shows each Chrome window with its profile and its Assignment. (pending live demo)

## Comments

**2026-11-09, implementation (pending live demo):**
- **Identity:** a Layout `WindowIdentity` is now `bundleID`, `isFullscreen`, and either `chromeProfile` + `name` (Chrome) or `title` (other apps). Layout stays version 1: old files still decode (`isFullscreen` defaults to false); old Chrome Assignments keyed by title match nothing and drop out on the next Save.
- **Matching** (`Engine/WindowMatching.swift`): 1) exact name (Chrome) or title (others); 2) an unnamed Chrome Assignment takes a window with the same profile and fullscreen flag, oldest window first; 3) another app's Assignment takes the one remaining window of its app and fullscreen flag whatever its title. Extras match nothing and are never moved. `status` now shows each window's `name` and `assignment` (its Space).
- **Auto-naming:** Save names unnamed Chrome windows that share a profile and fullscreen flag ("Work 1", "Work 2"), plus any whose profile is unknown ("Chrome 1"). Denied Automation skips naming; Save still succeeds and its reply says why. Fullscreen windows still aren't saved (ticket 10).
- **`name_window`** on MCP names a Chrome window through the port (refused for other apps) and renames its Assignment in place. Named Assignments outlive their window; unnamed ones drop on Save.
- **Adapter:** Chrome AppleScript lives in `MacOS/ChromeScripting.swift`. It reads `given name` and sets it, finding each window by title plus bounds because AppleScript window IDs aren't WindowServer IDs. It only reads when Automation is already granted. Naming asks for permission, and that prompt blocks until the user answers. `Info.plist` gains `NSAppleEventsUsageDescription`.
- **Chrome profiles Doctor fix (decision):** I didn't find a SIP-on way to read the avatar button of a window on a hidden desktop. yabai's remote-token trick is unverified and adds more private API. Instead:
  - The adapter remembers each window's profile from the last time it was visible. A window ID lives as long as its window.
  - A profile still unknown is treated as unknown in matching: the window can only match by name, and Save gives it one.
  - The "Chrome profiles" check now fails only when Accessibility reached a window and still found no profile, which means Chrome changed. Windows on hidden desktops are a passing finding listed in the details.
  - A new "Chrome Automation" check fails when Automation is denied and is skipped when the user hasn't been asked yet or Chrome isn't running.
- Tests: 7 new in `ChromeIdentityTests` (30 total).

