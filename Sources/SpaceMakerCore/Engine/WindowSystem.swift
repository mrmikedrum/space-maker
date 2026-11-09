import Foundation

/// The single seam between the engine and macOS. `MacWindowSystem` is the real adapter; tests use a fake.
@MainActor
public protocol WindowSystem: AnyObject {
    /// Every connected display, with its desktops in Mission Control order.
    func readDisplays() -> [WindowSystemDisplay]
    /// Every window on any desktop.
    func readWindows() -> [WindowSystemWindow]
    /// The focused window of the frontmost app, if it has one.
    func readFrontmostWindow() -> UInt32?

    /// Moves a window to a native desktop. Returns false if the move didn't land.
    func moveWindow(_ windowID: UInt32, toDesktop desktopID: UInt64) -> Bool

    /// Sets a window's position and size, in screen points. Returns false if macOS didn't apply it.
    func setFrame(_ windowID: UInt32, to frame: WindowFrame) -> Bool

    /// Sets a Chrome window's name (Chrome's `given name`), which Chrome keeps across a relaunch.
    /// May ask the user for Automation permission.
    func setChromeWindowName(_ windowID: UInt32, to name: String) -> WindowNamingResult

    /// Where the port delivers events. The engine sets this when it's created.
    var onEvent: (@MainActor (WindowSystemEvent) -> Void)? { get set }

    /// The clock: runs `action` on the main actor once `delay` seconds have passed.
    func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void)

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

public enum WindowNamingResult: Equatable, Sendable {
    case named
    /// The user hasn't allowed Space Maker to automate Chrome; the reason says how to fix it.
    case denied(String)
    case failed(String)
}

/// Something that happened in macOS that the engine reacts to.
public enum WindowSystemEvent: Equatable, Sendable {
    /// The desktop showing on some display changed. macOS doesn't say which.
    case activeSpaceChanged
    /// The user clicked the Pin mirror of this window (a click, not a drag).
    case pinClicked(UInt32)
    /// A window appeared: newly opened, or brought back by an app that relaunched.
    case windowAppeared(UInt32)
    /// The window closed.
    case windowClosed(UInt32)
    /// Displays were connected, disconnected or rearranged. macOS sends these in bursts while it
    /// rearranges desktops, so they say only that something changed.
    case displaysReconfigured
}

public struct WindowSystemDisplay: Equatable, Sendable {
    /// Stable identity (the display UUID).
    public var id: String
    /// Vendor, model and serial number, the fallback identity when WindowServer gives a display a new UUID.
    /// Nil when the display reports no serial number.
    public var hardwareID: String?
    public var name: String
    public var isBuiltIn: Bool
    public var desktops: [WindowSystemDesktop]
    /// The part of the display windows can use (without the menu bar and Dock), in screen points.
    /// Saved positions are relative to it. Empty if it couldn't be read.
    public var visibleFrame: WindowFrame

    public init(
        id: String, hardwareID: String? = nil, name: String, isBuiltIn: Bool, desktops: [WindowSystemDesktop],
        visibleFrame: WindowFrame = .zero
    ) {
        self.id = id
        self.hardwareID = hardwareID
        self.name = name
        self.isBuiltIn = isBuiltIn
        self.desktops = desktops
        self.visibleFrame = visibleFrame
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
    /// The name the window was given (Chrome's `given name`), if it has one and it could be read.
    /// Chrome shows a named window's name as its title.
    public var name: String?
    /// The window's position and size in screen points, if it could be read.
    public var frame: WindowFrame?

    public init(
        id: UInt32, bundleID: String, appName: String, title: String, desktopID: UInt64?,
        isFullscreen: Bool, chromeProfile: ChromeProfile, isStandard: Bool, name: String? = nil,
        frame: WindowFrame? = nil
    ) {
        self.id = id
        self.bundleID = bundleID
        self.appName = appName
        self.title = title
        self.desktopID = desktopID
        self.isFullscreen = isFullscreen
        self.chromeProfile = chromeProfile
        self.isStandard = isStandard
        self.name = name
        self.frame = frame
    }
}

/// A rectangle in screen points: global coordinates with the origin at the top left of the main display, y downwards.
public struct WindowFrame: Codable, Equatable, Sendable {
    public static let zero = WindowFrame(x: 0, y: 0, width: 0, height: 0)

    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }
}
