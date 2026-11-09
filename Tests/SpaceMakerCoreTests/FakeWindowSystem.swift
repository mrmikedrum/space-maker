import SpaceMakerCore

/// A scriptable stand-in for macOS. Tests set `displays` and `windows` to describe the world.
@MainActor
final class FakeWindowSystem: WindowSystem {
    var displays: [WindowSystemDisplay] = []
    var windows: [WindowSystemWindow] = []

    func readDisplays() -> [WindowSystemDisplay] { displays }
    func readWindows() -> [WindowSystemWindow] { windows }
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
        isStandard: Bool = true
    ) -> Self {
        Self(
            id: id, bundleID: bundleID, appName: appName, title: title, desktopID: desktop,
            isFullscreen: fullscreen, chromeProfile: chromeProfile, isStandard: isStandard
        )
    }

    static func chrome(_ id: UInt32, profile: ChromeProfile, title: String, desktop: UInt64?, fullscreen: Bool = false) -> Self {
        app(id, "com.google.Chrome", "Google Chrome", title: title, desktop: desktop, fullscreen: fullscreen, chromeProfile: profile)
    }
}
