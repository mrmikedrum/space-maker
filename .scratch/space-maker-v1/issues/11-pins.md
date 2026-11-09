# 11: Pins

**What to build:** The user Pins the frontmost window from the menu bar, or any window via `pin`/`unpin` on MCP. A floating live mirror of that window appears on every regular Space. It does not appear over fullscreen-app desktops.

The user can drag and resize the mirror. It hides while the real window is visible on the active Space, and clicking it switches to the real window's Space and focuses the window.

Several Pins can exist at once. A Pin disappears when its window closes. Pinning a fullscreen window is refused with a reason. Pins are not saved.

**Blocked by:** 02

**Status:** ready-for-agent

- [x] Engine tests against the fake cover: show and hide as the active Space changes; a click focuses the window and switches Space; closing the source window removes its Pin; a fullscreen window is refused; multiple Pins.
- [x] If the Doctor's Screen Recording or capture check fails, `pin` is disabled and reports why.
- [ ] Demo on the real Mac: Pin a Chrome window and switch Spaces. The mirror stays visible. Clicking it lands on the real window. (Pending live demo.)

## Comments

- Implemented test-first against the fake `WindowSystem` (`Tests/SpaceMakerCoreTests/PinTests.swift`). The port gained actions (show/hide/stop Pin mirror, focus window, read frontmost window) and events (active Space changed, Pin clicked, window closed). `pin`/`unpin` take a `window` handle over the socket and MCP; `status` lists pinned handles. Pins live only in the engine and are never written to the Layout.
- Click → focus: the fake mirrors macOS, where focusing a window on another desktop switches to it. The adapter does this with SkyLight `_SLPSSetFrontProcessWithOptions` + `SLPSPostEventRecordTo` (yabai's approach, needed because Accessibility can't reach windows on hidden desktops), falling back to activating the app. These symbols join the Doctor's symbol check. Unverified live.
- New Doctor check "Screen capture" (one `desktopIndependentWindow` screenshot). If it fails the menu bar calls `Engine.disablePins(because:)`; a skip (no window to capture) leaves Pins on.
- The mirror panel (`MacOS/PinMirror.swift`) leaves out `.fullScreenAuxiliary`, so it should stay off fullscreen-app desktops, and capture pauses while the mirror is hidden. Drag moves it, the edges resize it, and a click without a drag focuses the window. A closed window is noticed when its stream stops, and on the next Space change. All of this is pending the live demo.

