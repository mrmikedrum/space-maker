/// What `status` reports: the world as Space Maker sees it.
public struct Status: Codable, Equatable, Sendable {
    /// The connected known displays: the built-in one and every remembered one.
    public var displaySetup: [DisplayStatus]
    /// Connected displays that belong to no Display Setup.
    public var guestDisplays: [DisplayStatus]
    public var windows: [WindowStatus]
    /// Handles of the pinned windows, in the order they were pinned.
    public var pins: [String]
    /// Windows that differ from the Layout in a way Restore, Save or Ignore can settle.
    public var drift: [DriftStatus]
    /// Drift Space Maker can't fix itself; only the user can, by rearranging and then Saving.
    public var softDrift: [SoftDriftStatus]
}

public struct DisplayStatus: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var desktops: [DesktopStatus]

    public init(id: String, name: String, desktops: [DesktopStatus]) {
        self.id = id
        self.name = name
        self.desktops = desktops
    }
}

public struct DesktopStatus: Codable, Equatable, Sendable {
    /// 1-based position on its display, counting regular and fullscreen desktops, as Mission Control shows them.
    public var number: Int
    public var kind: DesktopKind
    public var isCurrent: Bool
    /// The Space this desktop's position holds in the saved Arrangement, if any.
    public var space: String?

    public init(number: Int, kind: DesktopKind, isCurrent: Bool, space: String? = nil) {
        self.number = number
        self.kind = kind
        self.isCurrent = isCurrent
        self.space = space
    }
}

/// Where a window is: a desktop by its position on a display.
public struct DesktopReference: Codable, Equatable, Sendable {
    public var display: String
    public var number: Int

    public init(display: String, number: Int) {
        self.display = display
        self.number = number
    }
}

public struct WindowStatus: Codable, Equatable, Sendable {
    /// Short and stable for as long as the window lives.
    public var handle: String
    public var app: String
    public var bundleID: String
    /// The Chrome profile name, `"unknown"` when it couldn't be read, nil for other apps.
    public var chromeProfile: String?
    public var isFullscreen: Bool
    public var title: String
    /// The window's name (Chrome's `given name`), if it has one.
    public var name: String?
    /// Nil when the window isn't on exactly one known desktop.
    public var desktop: DesktopReference?
    /// The Space its Assignment puts it on; nil when it has no Assignment.
    public var assignment: String?

    public init(
        handle: String, app: String, bundleID: String, chromeProfile: String?,
        isFullscreen: Bool, title: String, name: String? = nil, desktop: DesktopReference?, assignment: String? = nil
    ) {
        self.handle = handle
        self.app = app
        self.bundleID = bundleID
        self.chromeProfile = chromeProfile
        self.isFullscreen = isFullscreen
        self.title = title
        self.name = name
        self.desktop = desktop
        self.assignment = assignment
    }
}
