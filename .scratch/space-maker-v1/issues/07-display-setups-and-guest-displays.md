# 07: Display Setups and Guest Displays

**What to build:** Space Maker tells "laptop alone" apart from "laptop plus the 4K monitor".
- A display other than the built-in one becomes known only through `remember_display` (MCP) or "Remember this display" (menu bar). Every other display is a Guest Display, and Space Maker never puts anything on one.
- Each Display Setup has its own Arrangement, and Save updates only the current Display Setup's Arrangement.
- A Space resolves to its slot ("the Nth regular desktop on display D") in the current Arrangement, never to a native desktop (ADR 0003). Restore therefore follows the current Arrangement, whatever order macOS has left the desktops in.
- If the current Display Setup has no saved Arrangement, the user is told and nothing moves.
- A display with too few desktops is Soft Drift. Extra desktops are ignored.

**Blocked by:** 03, 06

**Status:** ready-for-agent

- [x] Displays are identified by UUID, falling back to vendor, model and serial.
- [x] Engine tests against the fake cover: undock merging followed by Restore against the Laptop Arrangement; a redock in shuffled order followed by Restore against the Docked Arrangement; a Guest Display excluded and its windows reported as Drift; an unknown Display Setup suppressing Restore; a missing desktop reported as Soft Drift; Save on one Display Setup leaving the other untouched.
- [ ] Demo on the real Mac: Save while docked, undock, and Restore all. Windows land in the Laptop slots. (pending live demo)

## Comments

- Built test-first against the fake `WindowSystem` with a real Layout in a temp folder (`DisplaySetupTests`, 10 tests). The fake gains `undock` (first desktop collapses into the laptop's first, the rest appended), `redock` (desktops return in a given, shuffled order; unknown IDs are new empty desktops, so a missing one can be simulated) and `disconnect`.
- The Layout gains `knownDisplays` (`id` = UUID when remembered, `hardwareID` = vendor:model:serial, `name`). The built-in display stays implicit. Older Layouts without the key load unchanged; the version stays 1 since the change is additive (keeps clear of ticket 04's schema work).
- A connected display is known if built-in, or its UUID or (failing that) hardware ID matches a remembered one; Display Setups and Arrangements always name it by its remembered ID. Hardware ID is nil without a serial number, so two identical serial-less monitors aren't confused. Every other display is a Guest Display: left out of the Display Setup key, Save and Space resolution, so nothing is ever moved onto it, and its windows show as `moved`/`new` Drift.
- `remember_display` (engine, MCP, and a "Remember This Display" menu item per Guest Display) takes a Guest Display's id from `status`, or none when exactly one is connected. An unknown Display Setup refuses Restore/`move_window` with "nothing was moved", and `status` lists it as Soft Drift with a "arrange, then Save" hint.
- Slot resolution (ADR 0003) and missing-desktop Soft Drift were already in place from 03/06; the undock, shuffled-redock, too-few-desktops and extra-desktops tests confirm them across Display Setups.
- Real-Mac demo is pending live demo (user away). Returning windows home when a Guest Display disconnects is ticket 08.

