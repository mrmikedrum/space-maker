# 02: `status` over MCP, plus the menu bar shell

**What to build:** The user adds the Space Maker MCP server to Claude Code, calls `status`, and sees their real displays, desktops (regular and fullscreen, in order) and windows. Each window has a short handle, its app, its Chrome profile when one can be read, a fullscreen flag, a title, and its current desktop. `doctor` also works over MCP.

The menu bar app launches at login, has Doctor and "Open Layout file" items, and its icon shows a warning symbol when the Doctor fails (superseded "turns red" during live testing: a tinted icon stopped following the menu bar's appearance).

This ticket introduces the engine, the `WindowSystem` port with its real macOS adapter and a fake, the Unix-socket command relay, and the stateless stdio MCP shim (ADR 0002). Until ticket 07, every display other than the built-in one is reported as a Guest Display.

**Blocked by:** 01

**Status:** resolved

- [x] Engine tests run against the fake `WindowSystem` and pass. They assert `status` output only.
- [x] One smoke test: a command makes a round trip through the socket to the shim.
- [x] When the app isn't running, the MCP shim returns "Space Maker isn't running".
- [x] The app is menu-bar-only (no Dock icon) and registered to launch at login.` are in place, not yet observed on the real Mac.)
- [x] If the Chrome profile can't be read, it is reported as unknown and recorded as a Doctor finding.
- [x] `status` against the user's real Mac matches what Mission Control shows.

## Comments

**2026-11-09, implementation (pending live demo):** Added the engine (`SpaceMakerCore/Engine`), the read-only `WindowSystem` port with its macOS adapter `MacWindowSystem` (`SpaceMakerCore/MacOS`), the newline-delimited JSON relay over `~/Library/Application Support/SpaceMaker/command.sock` (`SpaceMakerCore/Relay`), the `space-maker-mcp` stdio executable on `modelcontextprotocol/swift-sdk` 0.9.0 (tools `status` and `doctor`), and the menu bar shell (Run Doctor, Open Layout File, Quit; red icon on a Doctor failure; Doctor at launch). `scripts/build-app.sh` now bundles and signs `Contents/MacOS/space-maker-mcp`; register that path with Claude Code as a stdio MCP server. 8 Swift Testing tests: 6 engine `status` tests against the fake, 2 shim smoke tests (round trip, and "Space Maker isn't running.").

Not yet seen on the real Mac (user away), so these need the live demo:
- Accessibility only reaches windows on visible desktops, so a Chrome window on another desktop reports an unknown profile and fails the new "Chrome profiles" Doctor check. That turns the icon red whenever Chrome windows sit on hidden desktops. Ticket 04 may need yabai's remote-token window enumeration, or this check may need to become a non-failing finding.
- The profile is read by matching the avatar button's accessible text against the names in Chrome's `Local State` (`profile.info_cache`). With a single profile it's taken directly. The matching is unverified.
- Windows on desktops Accessibility can't reach are assumed standard, so a hidden-desktop panel may show up in `status`.
- "Open Layout File" reveals `~/.config/space-maker/` until ticket 03 writes `layout.json`.

**2026-11-09, live testing:** the "red icon" described above was replaced by an untinted warning template symbol, so the icon follows the menu bar's light or dark appearance. Spec updated to match.

**Resolution:** Verified live 2026-11-09: menu-bar-only app and `status` matching Mission Control (after filtering Chrome's untitled helper windows). Launch at login is registered but wasn't observed across a login.
