# 02: `status` over MCP, plus the menu bar shell

**What to build:** The user adds the Space Maker MCP server to Claude Code, calls `status`, and sees their real displays, desktops (regular and fullscreen, in order) and windows. Each window has a short handle, its app, its Chrome profile when one can be read, a fullscreen flag, a title, and its current desktop. `doctor` also works over MCP.

The menu bar app launches at login, has Doctor and "Open Layout file" items, and its icon turns red when the Doctor fails.

This ticket introduces the engine, the `WindowSystem` port with its real macOS adapter and a fake, the Unix-socket command relay, and the stateless stdio MCP shim (ADR 0002). Until ticket 07, every display other than the built-in one is reported as a Guest Display.

**Blocked by:** 01

**Status:** ready-for-agent

- [ ] Engine tests run against the fake `WindowSystem` and pass. They assert `status` output only.
- [ ] One smoke test: a command makes a round trip through the socket to the shim.
- [ ] When the app isn't running, the MCP shim returns "Space Maker isn't running".
- [ ] The app is menu-bar-only (no Dock icon) and registered to launch at login.
- [ ] If the Chrome profile can't be read, it is reported as unknown and recorded as a Doctor finding.
- [ ] `status` against the user's real Mac matches what Mission Control shows.
