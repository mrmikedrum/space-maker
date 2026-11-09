import Foundation

/// Saved positions: each window's position and size per Display Setup, relative to the display it's on.
extension Engine {
    /// How far, in points, a window may be from its saved position before it counts as Drift.
    static let positionTolerance = 2.0

    /// The visible frame of the display showing `desktop`, if it's known and was readable.
    static func visibleFrame(ofDisplayWith desktop: UInt64?, in displays: [WindowSystemDisplay]) -> WindowFrame? {
        guard let desktop, let display = displays.first(where: { $0.desktops.contains { $0.id == desktop } }),
              display.visibleFrame.width > 0, display.visibleFrame.height > 0
        else { return nil }
        return display.visibleFrame
    }

    /// The window's current position relative to the display it's on, if both can be read.
    static func relativeFrame(of window: WindowSystemWindow, in displays: [WindowSystemDisplay]) -> RelativeFrame? {
        guard let frame = window.frame, let display = visibleFrame(ofDisplayWith: window.desktopID, in: displays) else { return nil }
        return RelativeFrame(frame, on: display)
    }

    /// Where `assignment` puts its window on `desktop` in this Display Setup, or nil if no position was saved here.
    func savedFrame(of assignment: Assignment, on desktop: UInt64, displays: [WindowSystemDisplay]) -> WindowFrame? {
        guard let relative = assignment.frame(in: displaySetupKey(displays)),
              let display = Self.visibleFrame(ofDisplayWith: desktop, in: displays)
        else { return nil }
        return relative.absolute(on: display)
    }

    static func isAt(_ frame: WindowFrame?, _ target: WindowFrame) -> Bool {
        guard let frame else { return false }
        return [frame.x - target.x, frame.y - target.y, frame.width - target.width, frame.height - target.height]
            .allSatisfy { abs($0) <= positionTolerance }
    }

    /// What it takes to put a window where its Assignment says in this Display Setup.
    struct WindowPlan {
        var target: UInt64
        var needsMove: Bool
        /// The saved position to apply, if the window needs putting there.
        var frame: WindowFrame?

        var isNeeded: Bool { needsMove || frame != nil }
    }

    enum PlanOutcome {
        case done
        case moveFailed
        case frameFailed
    }

    /// `displays` are the known displays.
    func plan(_ window: WindowSystemWindow, _ assignment: Assignment, on target: UInt64, displays: [WindowSystemDisplay]) -> WindowPlan {
        let needsMove = window.desktopID != target
        var frame = savedFrame(of: assignment, on: target, displays: displays)
        // A window that stays on its display keeps its frame through a move, so the frame read now is still current.
        let changesDisplay = needsMove && Self.visibleFrame(ofDisplayWith: window.desktopID, in: displays) != Self.visibleFrame(ofDisplayWith: target, in: displays)
        if let saved = frame, !changesDisplay, Self.isAt(window.frame, saved) { frame = nil }
        return WindowPlan(target: target, needsMove: needsMove, frame: frame)
    }

    /// Moves the window to its Space, then puts it at its saved position. Failures become Soft Drift.
    func carryOut(_ plan: WindowPlan, for windowID: UInt32) -> PlanOutcome {
        if plan.needsMove {
            guard windowSystem.moveWindow(windowID, toDesktop: plan.target) else {
                failedMoves.insert(windowID)
                return .moveFailed
            }
            failedMoves.remove(windowID)
        }
        if let frame = plan.frame {
            // A window can keep its position through a move between displays; then there's nothing to set,
            // which matters because Accessibility can't reach a window on a hidden desktop to set it.
            if plan.needsMove, Self.isAt(windowSystem.readWindows().first { $0.id == windowID }?.frame, frame) {
                failedFrames.remove(windowID)
                return .done
            }
            guard windowSystem.setFrame(windowID, to: frame) else {
                failedFrames.insert(windowID)
                return .frameFailed
            }
            failedFrames.remove(windowID)
        }
        return .done
    }
}
