# Spaces are positions in each Display Setup's Arrangement, not native desktops

A Space name never binds to a particular native macOS desktop (its UUID or ManagedSpaceID). Instead, each Display Setup's Arrangement maps Space names to positions on displays, and Restore moves windows into whichever desktop currently fills each position.

macOS merges an external display's desktops onto the laptop when the display detaches, and moves them back unreliably when it reattaches. Nobody confirms that desktop identity survives this, and with SIP enabled Space Maker cannot move or reorder desktops. So following desktop identity would leave the user living with macOS's shuffling, while slots let Restore undo it. The cost is extra window moves on every Display Setup change.
