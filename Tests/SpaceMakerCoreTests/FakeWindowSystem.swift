import Foundation
import SpaceMakerCore

/// A scriptable stand-in for macOS. Tests set `displays` and `windows` to describe the world.
@MainActor
final class FakeWindowSystem: WindowSystem {
    var displays: [WindowSystemDisplay] = []
    var windows: [WindowSystemWindow] = []

    func readDisplays() -> [WindowSystemDisplay] { displays }
    func readWindows() -> [WindowSystemWindow] { windows }

    /// Windows macOS refuses to move, as when the bridged move stops working.
    var unmovableWindows: Set<UInt32> = []

    func moveWindow(_ windowID: UInt32, toDesktop desktopID: UInt64) -> Bool {
        guard !unmovableWindows.contains(windowID),
              displays.contains(where: { $0.desktops.contains { $0.id == desktopID } })
        else { return false }
        move(windowID, to: desktopID)
        return true
    }

    /// The user (or macOS) moves a window by hand.
    func move(_ windowID: UInt32, to desktopID: UInt64) {
        guard let index = windows.firstIndex(where: { $0.id == windowID }) else { return }
        windows[index].desktopID = desktopID
    }

    func desktop(of windowID: UInt32) -> UInt64? {
        windows.first { $0.id == windowID }?.desktopID
    }

    func window(_ windowID: UInt32) -> WindowSystemWindow? {
        windows.first { $0.id == windowID }
    }

    /// Whether the user denied Space Maker Automation permission for Chrome.
    var chromeAutomationDenied = false

    /// Like Chrome, a named window's title becomes its name.
    func setChromeWindowName(_ windowID: UInt32, to name: String) -> WindowNamingResult {
        if chromeAutomationDenied { return .denied("Automation for Google Chrome isn't allowed.") }
        guard let index = windows.firstIndex(where: { $0.id == windowID && $0.chromeProfile != .notChrome }) else {
            return .failed("No such Chrome window.")
        }
        windows[index].name = name
        windows[index].title = name
        return .named
    }

    /// Quits and relaunches Chrome as macOS 15 does: session restore brings every window back,
    /// names included, with fresh window IDs (`id + offset`) and every normal window on the current desktop.
    func relaunchChrome(idOffset: UInt32 = 1000) {
        let current = displays.flatMap(\.desktops).first(where: \.isCurrent)?.id
        for index in windows.indices where windows[index].chromeProfile != .notChrome {
            windows[index].id += idOffset
            if !windows[index].isFullscreen { windows[index].desktopID = current }
        }
    }
}

extension WindowSystemDisplay {
    static func builtIn(desktops: [WindowSystemDesktop]) -> Self {
        Self(id: "built-in", name: "Built-in Retina Display", isBuiltIn: true, desktops: desktops)
    }

    static func external(_ id: String, name: String, desktops: [WindowSystemDesktop]) -> Self {
        Self(id: id, name: name, isBuiltIn: false, desktops: desktops)
    }
}

extension WindowSystemWindow {
    static func app(
        _ id: UInt32,
        _ bundleID: String,
        _ appName: String,
        title: String,
        desktop: UInt64?,
        fullscreen: Bool = false,
        chromeProfile: ChromeProfile = .notChrome,
        isStandard: Bool = true,
        name: String? = nil
    ) -> Self {
        Self(
            id: id, bundleID: bundleID, appName: appName, title: name ?? title, desktopID: desktop,
            isFullscreen: fullscreen, chromeProfile: chromeProfile, isStandard: isStandard, name: name
        )
    }

    static func chrome(
        _ id: UInt32, profile: ChromeProfile, title: String, desktop: UInt64?, fullscreen: Bool = false, name: String? = nil
    ) -> Self {
        app(id, "com.google.Chrome", "Google Chrome", title: title, desktop: desktop, fullscreen: fullscreen, chromeProfile: profile, name: name)
    }
}

extension URL {
    /// A Layout file location of its own, so tests never touch the user's real Layout.
    static func temporaryLayout() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("space-maker-tests-\(UUID().uuidString)/layout.json")
    }
}
