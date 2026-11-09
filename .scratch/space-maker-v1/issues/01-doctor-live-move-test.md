# 01: Doctor: live move test

**What to build:** Running Space Maker's Doctor from the command line on the user's Mac produces a markdown report in the Space Maker logs folder. The report says plainly whether the SIP-on bridged window move works on this macOS build. To get there, this ticket sets up the project skeleton: the signed menu-bar-only app bundle, a separate move-test helper app that owns one window, and the component that confines all private SkyLight access (ADR 0001). The report decides whether the user upgrades to Tahoe before anything else is built. See the spec: Doctor; Further Notes for the platform facts.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The app is signed with the user's Apple Development identity, so Accessibility and Screen Recording grants survive a rebuild.
- [ ] Doctor checks: OS build, TCC grants, the presence of every private symbol and class used (including the non-exported one, resolved at runtime), display and desktop enumeration, and the live move test.
- [ ] Live move test: the helper's window moves to another regular desktop and back. Each move is verified by asking SkyLight which desktop the window is on.
- [ ] Each check passes or fails on its own, with a readable reason. A missing symbol or permission never crashes the Doctor.
- [ ] The report is self-contained and written so an agent can act on it: environment, each check's result, error details, suspected cause.
- [ ] The ticket ends by telling the user which TCC grants to give and what the report concluded on 15.4.1.
