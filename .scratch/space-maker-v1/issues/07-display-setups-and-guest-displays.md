# 07: Display Setups and Guest Displays

**What to build:** Space Maker tells "laptop alone" apart from "laptop plus the 4K monitor".
- A display other than the built-in one becomes known only through `remember_display` (MCP) or "Remember this display" (menu bar). Every other display is a Guest Display, and Space Maker never puts anything on one.
- Each Display Setup has its own Arrangement, and Save updates only the current Display Setup's Arrangement.
- A Space resolves to its slot ("the Nth regular desktop on display D") in the current Arrangement, never to a native desktop (ADR 0003). Restore therefore follows the current Arrangement, whatever order macOS has left the desktops in.
- If the current Display Setup has no saved Arrangement, the user is told and nothing moves.
- A display with too few desktops is Soft Drift. Extra desktops are ignored.

**Blocked by:** 03, 06

**Status:** ready-for-agent

- [ ] Displays are identified by UUID, falling back to vendor, model and serial.
- [ ] Engine tests against the fake cover: undock merging followed by Restore against the Laptop Arrangement; a redock in shuffled order followed by Restore against the Docked Arrangement; a Guest Display excluded and its windows reported as Drift; an unknown Display Setup suppressing Restore; a missing desktop reported as Soft Drift; Save on one Display Setup leaving the other untouched.
- [ ] Demo on the real Mac: Save while docked, undock, and Restore all. Windows land in the Laptop slots.
