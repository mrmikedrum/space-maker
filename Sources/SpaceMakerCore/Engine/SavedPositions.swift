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
}
