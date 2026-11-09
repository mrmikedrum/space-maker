import Foundation

/// Where the engine is between a display change and the automatic Restore that follows it.
struct DisplayChangeProgress {
    /// Bumped by every reconfiguration event, so work scheduled for an earlier event lapses.
    var generation = 0
    /// The desktops as last polled, waiting for a second read that matches.
    var lastRead: [DesktopsRead]?
    var reads = 0
    /// The last display change never settled, so no automatic Restore ran: Soft Drift until a later one settles or the user Restores.
    var neverSettled = false
    /// Where windows were, by window ID, the last time the engine looked at the world with the displays settled.
    /// macOS can shove windows before it reports a reconfiguration, so this is kept up to date beforehand.
    var stableFrames: [UInt32: FrameBefore] = [:]
    /// `stableFrames` as they were when the first reconfiguration event since the last automatic Restore arrived.
    /// While this is set, a display change is under way and `stableFrames` is left alone.
    var framesBefore: [UInt32: FrameBefore]?
}

/// A window's position before a display change, and the display it was on.
struct FrameBefore {
    var display: String
    var frame: WindowFrame
}

/// One display's desktops as a settle poll sees them.
struct DesktopsRead: Equatable {
    var display: String
    var desktops: [UInt64]
    var kinds: [DesktopKind]
}

/// Automatic Restore on display change: debounce the reconfiguration events, wait until two consecutive
/// reads of the desktops match, then run a full Restore. Desktops that never settle get no Restore.
/// Windows with an Assignment but no saved position for the Display Setup go back to where they were before the
/// change, if they're still on the same known display.
extension Engine {
    /// How long reconfiguration events must stop before Space Maker looks at the desktops.
    static let displayChangeDebounce: TimeInterval = 1
    /// How often the desktops are read while waiting for them to settle.
    static let desktopSettlePollInterval: TimeInterval = 0.5
    /// Reads after which Space Maker stops waiting, without Restoring, until the next display change.
    static let desktopSettleMaxReads = 20

    func displaysReconfigured() {
        if displayChange.framesBefore == nil { displayChange.framesBefore = displayChange.stableFrames }
        displayChange.generation += 1
        displayChange.lastRead = nil
        displayChange.reads = 0
        let generation = displayChange.generation
        windowSystem.schedule(after: Self.displayChangeDebounce) { [weak self] in
            self?.pollDesktopsUntilSettled(generation)
        }
    }

    private func pollDesktopsUntilSettled(_ generation: Int) {
        guard generation == displayChange.generation else { return }  // a later event restarted the wait
        let read = windowSystem.readDisplays().map {
            DesktopsRead(display: $0.id, desktops: $0.desktops.map(\.id), kinds: $0.desktops.map(\.kind))
        }
        displayChange.reads += 1
        if read == displayChange.lastRead {
            displayChange.lastRead = nil
            displayChange.neverSettled = false
            restoreAutomatically(generation)
            return
        }
        // A Restore on a half-finished read would send windows to the wrong desktops, so give up and say so.
        if displayChange.reads >= Self.desktopSettleMaxReads {
            displayChange.lastRead = nil
            displayChange.neverSettled = true
            onChange?()
            return
        }
        displayChange.lastRead = read
        windowSystem.schedule(after: Self.desktopSettlePollInterval) { [weak self] in
            self?.pollDesktopsUntilSettled(generation)
        }
    }

    /// A full Restore nobody asked for: it runs only while automatic behaviour isn't paused.
    /// A change that settles while paused is not replayed on resume; Restore all catches up.
    /// `generation` is the display change whose desktops settled; a later change makes this lapse.
    private func restoreAutomatically(_ generation: Int) {
        guard generation == displayChange.generation else { return }  // a later change is settling afresh
        guard !isMovingWindows else {  // a Placement or Restore is under way: Restore once it's done
            windowSystem.schedule(after: Self.desktopSettlePollInterval) { [weak self] in self?.restoreAutomatically(generation) }
            return
        }
        let framesBefore = displayChange.framesBefore ?? [:]
        displayChange.framesBefore = nil
        if !isPaused {
            _ = restore(handle: nil)
            putBackFrames(framesBefore)
        }
        noteStableFrames()
    }

    /// Records where windows are now, unless a display change is under way (then the world may be half-rearranged).
    /// Called whenever the engine looks at the world: commands, status and window events.
    func noteStableFrames() {
        guard displayChange.framesBefore == nil, !isMovingWindows else { return }
        displayChange.stableFrames = currentFrames()
    }

    /// Every normal window's position and known display, keyed by window ID. Guest Displays are left out.
    private func currentFrames() -> [UInt32: FrameBefore] {
        let displays = knownDisplays(windowSystem.readDisplays())
        var result: [UInt32: FrameBefore] = [:]
        for window in windowSystem.readWindows() where window.isStandard && !window.isFullscreen {
            guard let frame = window.frame, let display = Self.display(of: window, in: displays) else { continue }
            result[window.id] = FrameBefore(display: display, frame: frame)
        }
        return result
    }

    private static func display(of window: WindowSystemWindow, in displays: [WindowSystemDisplay]) -> String? {
        displays.first { $0.desktops.contains { $0.id == window.desktopID } }?.id
    }

    /// Puts windows that macOS moved during the change back where they were, if they're still on the same known
    /// display, have an Assignment, and Restore doesn't own their position (no saved position for this Display Setup).
    /// Windows without an Assignment are never moved.
    private func putBackFrames(_ framesBefore: [UInt32: FrameBefore]) {
        guard !framesBefore.isEmpty, layoutProblem == nil, movesDisabledReason == nil else { return }
        let displays = windowSystem.readDisplays()
        guard resolvedSpaces(displays) != nil else { return }  // an unknown Display Setup gets no automatic Restore
        let setup = displaySetupKey(displays)
        let known = knownDisplays(displays)
        let windows = windowSystem.readWindows().filter(\.isStandard)
        let matches = Self.match(windows, to: layout.assignments)
        for window in windows where !window.isFullscreen && !isIgnored(window) {
            guard let before = framesBefore[window.id], Self.display(of: window, in: known) == before.display,
                  !Self.isAt(window.frame, before.frame),
                  let assignment = matches[window.id], layout.assignments[assignment].frame(in: setup) == nil
            else { continue }
            _ = movingWindows { windowSystem.setFrame(window.id, to: before.frame) }
        }
    }

    /// Soft Drift for a display change whose desktops never settled, if the last one didn't.
    var unsettledDisplayChangeNote: SoftDriftStatus? {
        guard displayChange.neverSettled else { return nil }
        return SoftDriftStatus(
            handle: nil, app: nil, title: nil,
            problem: "After the last display change, macOS kept rearranging desktops and they never settled, so Space Maker didn't Restore.",
            hint: "Once the desktops look settled, use Restore all. Space Maker tries again on the next display change."
        )
    }
}
