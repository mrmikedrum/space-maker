# Space Maker

A personal macOS utility that keeps specific windows on the user's named Spaces, across changes to which displays are connected, and keeps chosen windows visible everywhere.

## Places

**Space**:
A named place for windows, such as "Code" or "Comms". In each Display Setup a Space is a position on a display. Which native macOS desktop currently fills that position is irrelevant. Fullscreen-app desktops are never Spaces.
_Avoid_: Desktop, workspace, virtual workspace

**Display Setup**:
A particular combination of connected known displays, such as "laptop alone" or "laptop plus the 4K monitor". The set of Spaces stays the same across Display Setups; their Arrangement and window positions can differ.
_Avoid_: Profile (a Chrome profile is a different thing), monitor config

**Guest Display**:
A connected display the user has not remembered into any Display Setup, such as an AirPlay screen, Sidecar iPad or hotel monitor. Space Maker never puts anything on it, and its presence does not change the Display Setup.
_Avoid_: Temporary display, external display

**Arrangement**:
Which Spaces and which fullscreen windows sit on each display, in what order, for one Display Setup.
_Avoid_: Ordering, layout

## Windows

**Assignment**:
Where a specific window belongs: a Space, or for a fullscreen window its place in the Arrangement, plus its position in each Display Setup where one was saved. Each window has its own Assignment, even when one app has several windows.
_Avoid_: Rule, binding, app-binding

**Pin**:
A window kept visible on every Space and above other windows, as far as macOS allows. A Pin can be a stand-in for the window rather than the window itself; interacting with it takes the user to the real window. Pins are temporary.
_Avoid_: Sticky, float, PiP

**Ignored**:
A window or app the user has deliberately left untracked. Ignored windows never count as Drift.
_Avoid_: Excluded, hidden, unmanaged

## Saved state

**Layout**:
The saved desired state: every Arrangement and every Assignment.
_Avoid_: Config, profile, snapshot

**Save**:
Record how things currently are into the Layout.
_Avoid_: Apply, capture, commit

**Restore**:
Make things match the Layout for the current Display Setup.
_Avoid_: Apply, sync, enforce

**Placement**:
Restoring a single window at the moment it appears.
_Avoid_: Auto-assign

**Drift**:
Any difference between how things currently are and the Layout.
_Avoid_: Deviation, diff

**Soft Drift**:
Drift that Space Maker cannot fix itself, such as desktop order on a display. Only the user can resolve it, by rearranging and then Saving.
_Avoid_: Warning, unfixable drift

## Health

**Doctor**:
Space Maker's self-check of everything it relies on in macOS, ending in a report the user can hand to an agent. Its **Live move test** moves a window owned by another process between desktops and back.
_Avoid_: Health check, diagnostics, self-test
