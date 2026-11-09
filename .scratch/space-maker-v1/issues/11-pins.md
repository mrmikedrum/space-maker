# 11: Pins

**What to build:** The user Pins the frontmost window from the menu bar, or any window via `pin`/`unpin` on MCP. A floating live mirror of that window appears on every regular Space. It does not appear over fullscreen-app desktops.

The user can drag and resize the mirror. It hides while the real window is visible on the active Space, and clicking it switches to the real window's Space and focuses the window.

Several Pins can exist at once. A Pin disappears when its window closes. Pinning a fullscreen window is refused with a reason. Pins are not saved.

**Blocked by:** 02

**Status:** ready-for-agent

- [ ] Engine tests against the fake cover: show and hide as the active Space changes; a click focuses the window and switches Space; closing the source window removes its Pin; a fullscreen window is refused; multiple Pins.
- [ ] If the Doctor's Screen Recording or capture check fails, `pin` is disabled and reports why.
- [ ] Demo on the real Mac: Pin a Chrome window and switch Spaces. The mirror stays visible. Clicking it lands on the real window.
