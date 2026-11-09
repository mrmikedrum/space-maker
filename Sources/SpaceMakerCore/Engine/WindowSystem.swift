/// The single seam between the engine and macOS. `MacWindowSystem` is the real adapter; tests use a fake.
///
/// Actions, events and the clock join the port as features need them.
@MainActor
public protocol WindowSystem: AnyObject {
    /// Every connected display, with its desktops in Mission Control order.
    func readDisplays() -> [WindowSystemDisplay]
    /// Every window on any desktop.
    func readWindows() -> [WindowSystemWindow]
    /// The focused window of the frontmost app, if it has one.
    func readFrontmostWindow() -> UInt32?

    /// Where the port delivers events. The engine sets this when it's created.
    var onEvent: (@MainActor (WindowSystemEvent) -> Void)? { get set }

    /// Raises and focuses the window. Like macOS itself, this switches to the window's desktop first.
    func focusWindow(_ windowID: UInt32)

    // MARK: Pin mirrors

    /// Shows the window's Pin mirror on every regular Space, starting it if needed.
    func showPinMirror(of windowID: UInt32)
    /// Hides the window's Pin mirror, keeping it ready to show again.
    func hidePinMirror(of windowID: UInt32)
    /// Removes the window's Pin mirror for good.
    func stopPinMirror(of windowID: UInt32)
}

/// Something that happened in macOS that the engine reacts to.
public enum WindowSystemEvent: Equatable, Sendable {
    /// The desktop showing on some display changed. macOS doesn't say which.
    case activeSpaceChanged
    /// The user clicked the Pin mirror of this window (a click, not a drag).
    case pinClicked(UInt32)
    /// The window closed.
    case windowClosed(UInt32)
}

public struct WindowSystemDisplay: Equatable, Sendable {
    /// Stable identity (the display UUID).
    public var id: String
    public var name: String
    public var isBuiltIn: Bool
    public var desktops: [WindowSystemDesktop]

    public init(id: String, name: String, isBuiltIn: Bool, desktops: [WindowSystemDesktop]) {
        self.id = id
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.desktops = desktops
    }
}

public enum DesktopKind: String, Codable, Equatable, Sendable {
    case regular
    case fullscreen
}

/// A native macOS desktop. Never a Space: a Space is a named slot (ADR 0003).
public struct WindowSystemDesktop: Equatable, Sendable {
    /// The native desktop ID; only meaningful while macOS keeps it.
    public var id: UInt64
    public var kind: DesktopKind
    public var isCurrent: Bool

    public init(id: UInt64, kind: DesktopKind, isCurrent: Bool) {
        self.id = id
        self.kind = kind
        self.isCurrent = isCurrent
    }
}

public enum ChromeProfile: Equatable, Sendable {
    case notChrome
    case known(String)
    /// A Chrome window whose profile couldn't be read.
    case unknown
}

public struct WindowSystemWindow: Equatable, Sendable {
    /// The WindowServer window ID.
    public var id: UInt32
    public var bundleID: String
    public var appName: String
    public var title: String
    /// The native desktop the window is on, if it's on exactly one.
    public var desktopID: UInt64?
    public var isFullscreen: Bool
    public var chromeProfile: ChromeProfile
    /// False for panels, dialogs and sheets.
    public var isStandard: Bool

    public init(
        id: UInt32, bundleID: String, appName: String, title: String, desktopID: UInt64?,
        isFullscreen: Bool, chromeProfile: ChromeProfile, isStandard: Bool
    ) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.desktopID = desktopID
        self.isFullscreen = isFullscreen
        self.chromeProfile = chromeProfile
        self.isStandard = isStandard
    }
}
