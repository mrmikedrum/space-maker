# 08: Automatic Restore on display change

**What to build:** When displays are connected or disconnected, Space Maker waits for the change to settle, then runs a full Restore by itself. Settling means debouncing the reconfiguration events, snapshotting window frames before the change, and polling desktops until two consecutive reads match.

Docking and undocking need nothing from the user. When an AirPlay or Sidecar Guest Display disconnects, any window the user moved onto it returns home. Pausing (ticket 05) also pauses this.

**Blocked by:** 07

**Status:** ready-for-agent

- [ ] Tests use the fake clock and never sleep. They cover: flapping reconfiguration events causing exactly one Restore; desktops that stay unsettled for several reads delaying Restore; a Guest Display session ending with windows back home; no automatic Restore while paused or on an unknown Display Setup.
- [ ] Demo on the real Mac: undock and redock with no further action. Everything ends up in its slot. (pending live demo)

## Comments

- Built test-first against the fake `WindowSystem` and a real Layout in a temp folder (`AutoRestoreTests`, 5 tests): undock with no further action; flapping events causing exactly one Restore (a dragged window isn't moved back later); desktops unsettled for several reads delaying Restore (the fake refuses moves while unsettled, so an early Restore would leave Soft Drift); an AirPlay Guest Display session ending with Keynote back home and an unassigned window left alone; an unknown Display Setup getting no automatic Restore.
- The `WindowSystem` port gains the clock (`schedule(after:_:)`) and a `displaysReconfigured` event. The macOS adapter posts it from `NSApplication.didChangeScreenParametersNotification` (public API) and schedules with `DispatchQueue.main.asyncAfter`. The fake gains `FakeClock` (`advance(by:)` runs due work in order; tests never sleep), `reconfigureDisplays()` and `unsettledReads`.
- Engine (`DisplayChange.swift`): every event restarts a 1 s debounce; then desktops are read every 0.5 s until two consecutive reads match (giving up after 20 reads and Restoring anyway), then a full Restore runs. A Guest Display needs nothing special: Restore sends every assigned window to its slot.
- Pause: ticket 05 hadn't landed when this was built. The only place automatic Restore runs is `Engine.restoreAutomatically()`, marked for `guard !isPaused`. See the merge note below.
- Deferred: "snapshot window frames before the change" needs frames in the port, which ticket 09 adds; it belongs with saved positions. Real-Mac demo is pending live demo (user away).
