import Foundation

/// One window's Drift, as `status` reports it.
public struct DriftStatus: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The window is away from the Space its Assignment names.
        case moved
        /// The window matches no Assignment.
        case new
        /// The window is on its Space but away from its saved position for this Display Setup.
        case position
    }

    public var kind: Kind
    public var handle: String
    public var app: String
    public var title: String
    /// The Space the window's Assignment names; nil for a new window.
    public var space: String?

    public init(kind: Kind, handle: String, app: String, title: String, space: String?) {
        self.kind = kind
        self.handle = handle
        self.app = app
        self.title = title
        self.space = space
    }
}

/// Drift Space Maker can't fix itself, as `status` reports it. It never lights the menu bar dot.
public struct SoftDriftStatus: Codable, Equatable, Sendable {
    /// The window concerned, if it's about one window.
    public var handle: String?
    public var app: String?
    public var title: String?
    public var problem: String
    /// What the user can do about it.
    public var hint: String

    public init(handle: String?, app: String?, title: String?, problem: String, hint: String) {
        self.handle = handle
        self.app = app
        self.title = title
        self.problem = problem
        self.hint = hint
    }
}

/// What Soft Drift is remembered against: displays, desktops, and which windows are where.
struct WorldSnapshot: Equatable {
    struct Place: Equatable {
        var window: UInt32
        var desktop: UInt64?
        var isFullscreen: Bool
        var frame: WindowFrame?
    }

    var displays: [WindowSystemDisplay]
    var places: [Place]

    init(displays: [WindowSystemDisplay], windows: [WindowSystemWindow]) {
        self.displays = displays
        places = windows.map { Place(window: $0.id, desktop: $0.desktopID, isFullscreen: $0.isFullscreen, frame: $0.frame) }
    }
}

/// Drift and Soft Drift: where the world differs from the Layout.
extension Engine {
    /// `windows` are the standard windows; panels, dialogs and sheets never drift, and Ignored windows are skipped.
    func drift(displays: [WindowSystemDisplay], windows: [WindowSystemWindow]) -> (drift: [DriftStatus], softDrift: [SoftDriftStatus]) {
        forgetSoftDriftIfWorldChanged(displays: displays, windows: windows)
        guard let desktops = resolvedSpaces(displays) else {
            return ([], [SoftDriftStatus(
                handle: nil, app: nil, title: nil,
                problem: "Nothing is saved for this Display Setup, so Space Maker won't move anything.",
                hint: "Arrange the windows and desktops the way you want them here, then Save."
            )])
        }
        let matches = Self.match(windows, to: layout.assignments)
        let known = knownDisplays(displays)
        var drift: [DriftStatus] = []
        var softDrift: [SoftDriftStatus] = []

        // Spaces this Display Setup's Arrangement has more of than its displays have desktops.
        let setupKey = displaySetupKey(displays)
        let arranged = layout.displaySetups.first { $0.displays == setupKey }?.arrangement.flatMap(\.spaces) ?? []
        for space in arranged where desktops[space] == nil {
            softDrift.append(SoftDriftStatus(
                handle: nil, app: nil, title: nil,
                problem: "Space “\(space)” has no desktop here, so its windows can't be restored.",
                hint: "Add a desktop for it in Mission Control, or move its windows and Save."
            ))
        }

        for window in windows where !window.isFullscreen && !isIgnored(window) {
            let assignment = matches[window.id].map { layout.assignments[$0] }
            let space = assignment?.space
            var kind = DriftStatus.Kind.new
            if let assignment, let space {
                guard let target = desktops[space], window.desktopID != nil else { continue }
                if window.desktopID == target {
                    // On its Space: Drift only if a position was saved for this Display Setup and the window is away from it.
                    guard let frame = savedFrame(of: assignment, on: target, displays: known), !Self.isAt(window.frame, frame) else { continue }
                    kind = .position
                } else {
                    kind = .moved
                }
                if failedMoves.contains(window.id) || failedFrames.contains(window.id) {
                    softDrift.append(SoftDriftStatus(
                        handle: handle(for: window.id), app: window.appName, title: window.title,
                        problem: kind == .moved ? "macOS wouldn't move it to “\(space)”." : "macOS wouldn't put it back at its saved position.",
                        hint: kind == .moved
                            ? "Move it there by hand, or Save to keep it where it is. Space Maker tries again when windows or desktops change."
                            : "Switch to “\(space)” and Restore, or Save to keep it as it is. Space Maker tries again when windows or desktops change."
                    ))
                    continue
                }
            }
            drift.append(DriftStatus(
                kind: kind, handle: handle(for: window.id),
                app: window.appName, title: window.title, space: space
            ))
        }
        return (drift, softDrift)
    }

    /// Soft Drift is never retried in a loop: only once something Space Maker can see has changed.
    func forgetSoftDriftIfWorldChanged(displays: [WindowSystemDisplay], windows: [WindowSystemWindow]) {
        guard let softDriftWorld, softDriftWorld != WorldSnapshot(displays: displays, windows: windows) else { return }
        failedMoves = []
        failedFrames = []
        self.softDriftWorld = nil
    }

    /// Called after Restore, so the Soft Drift it recorded holds until the world moves on.
    func rememberWorldForSoftDrift() {
        guard !failedMoves.isEmpty || !failedFrames.isEmpty else { softDriftWorld = nil; return }
        softDriftWorld = WorldSnapshot(
            displays: windowSystem.readDisplays(), windows: windowSystem.readWindows().filter(\.isStandard)
        )
    }
}

/// Ignore: windows and apps the user has deliberately left untracked.
extension Engine {
    func isIgnored(_ window: WindowSystemWindow) -> Bool {
        ignoredWindows.contains(window.id) || layout.ignoredApps.contains(window.bundleID)
    }

    /// Ignores the window with `handle` until it closes, or with `app`, its app always (saved in the Layout).
    func ignore(handle: String?, app: Bool) -> CommandReply {
        withLayout {
            guard let handle else {
                return CommandReply(text: "ignore needs a window handle (from status).", isError: true)
            }
            guard let window = window(withHandle: handle, in: windowSystem.readWindows().filter(\.isStandard)) else {
                return Self.unknownHandleReply(handle)
            }
            guard app else {
                ignoredWindows.insert(window.id)
                return CommandReply(text: "Ignoring \(handle) (\(window.appName) “\(window.title)”) until it closes.")
            }
            if !layout.ignoredApps.contains(window.bundleID) {
                layout.ignoredApps.append(window.bundleID)
                layout.ignoredApps.sort()
            }
            return committing("Always ignoring \(window.appName) (\(window.bundleID)). Remove it from ignoredApps in the Layout file to stop.")
        }
    }
}
