# Native Spaces, with SIP left enabled

Space Maker works on the user's real macOS Spaces rather than emulating virtual workspaces the way AeroSpace does. That keeps Mission Control, swipe gestures and Ctrl-arrow switching meaningful. It also never asks the user to disable System Integrity Protection.

## Consequences

- Moving another app's window to a Space depends on a private SkyLight operation. Apple has broken earlier versions of this twice (14.5, 15.0), so the move mechanism sits behind one replaceable component, and a self-check verifies it on every launch.
- Space Maker cannot make another app's window sticky or always-on-top, and cannot create, delete or reorder Spaces. A Pin is therefore a stand-in for the window (a live mirror), not the real window.
- Space Maker can only react to how macOS arranges Spaces across displays; it cannot command that arrangement.
