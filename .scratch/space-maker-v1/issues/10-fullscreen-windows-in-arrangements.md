# 10: Fullscreen windows in Arrangements

**What to build:** Save records fullscreen windows as items in the Arrangement, interleaved with Spaces in on-screen order, e.g. "Game fullscreen, Tasks, Personal, Work, Work fullscreen".

Restore leaves a fullscreen window alone if it's fullscreen on the right display. Otherwise it exits fullscreen, moves the window to the desktop just before its place, and re-enters fullscreen.

If a window is on the right display but in the wrong order (including one that should come before a display's first desktop), that is Soft Drift with a "drag it in Mission Control" hint.

**Blocked by:** 07, 06

**Status:** ready-for-agent

- [ ] Engine tests against the fake cover: undock and redock end with Work main and Game main fullscreen on the right display; a window already correct is never re-fullscreened; an order the fake can't achieve becomes Soft Drift; Restore doesn't loop.
- [ ] Demo on the real Mac: take Game main out of fullscreen, then Restore all. It goes back to fullscreen on the laptop display.
