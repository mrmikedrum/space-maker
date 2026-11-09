# 08: Automatic Restore on display change

**What to build:** When displays are connected or disconnected, Space Maker waits for the change to settle, then runs a full Restore by itself. Settling means debouncing the reconfiguration events, snapshotting window frames before the change, and polling desktops until two consecutive reads match.

Docking and undocking need nothing from the user. When an AirPlay or Sidecar Guest Display disconnects, any window the user moved onto it returns home. Pausing (ticket 05) also pauses this.

**Blocked by:** 07

**Status:** ready-for-agent

- [ ] Tests use the fake clock and never sleep. They cover: flapping reconfiguration events causing exactly one Restore; desktops that stay unsettled for several reads delaying Restore; a Guest Display session ending with windows back home; no automatic Restore while paused or on an unknown Display Setup.
- [ ] Demo on the real Mac: undock and redock with no further action. Everything ends up in its slot.
