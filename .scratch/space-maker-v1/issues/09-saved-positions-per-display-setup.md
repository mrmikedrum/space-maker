# 09: Saved positions per Display Setup

**What to build:** Save also records each window's position and size for the current Display Setup only, relative to the display it's on. Restore and Placement apply the saved position when one exists for the current Display Setup. Otherwise they enforce only the Space. The user never types a number. A window on the right Space but away from its saved position for the current Display Setup counts as Drift.

**Blocked by:** 07

**Status:** ready-for-agent

- [ ] Engine tests against the fake cover: a Save while docked leaves laptop positions untouched; Restore applies the right Display Setup's frame; windows without a saved frame keep their size and position; frames survive a resolution change because they are display-relative.
- [ ] Engine tests cover a window on the right Space but at the wrong position being reported as Drift, and one without a saved position for this Display Setup not being reported.
- [ ] Demo: arrange a window, Save, move and resize it, then Restore. It snaps back.
