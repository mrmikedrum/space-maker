import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// The real `WindowSystem`: reads this Mac's displays, desktops and windows.
///
/// Not unit tested; the Doctor is its test suite (spec, Testing Decisions).
@MainActor
public final class MacWindowSystem: WindowSystem {
    public static let chromeBundleID = WindowIdentity.chromeBundleID

    private let skyLight: SkyLight
    public var onEvent: (@MainActor (WindowSystemEvent) -> Void)?
    var mirrors: [UInt32: PinMirror] = [:]
    private var activeSpaceObserver: NSObjectProtocol?
    private var screenParametersObserver: NSObjectProtocol?
    private var appearanceObserver: WindowAppearanceObserver?

    /// Where each Chrome window's profile came from on the last read, for the Doctor.
    public enum ChromeProfileSource: Sendable {
        /// Read from the window's avatar button just now.
        case read
        /// Accessibility can't reach the window (it's on a hidden desktop); remembered from an earlier read.
        case remembered
        /// Accessibility can't reach the window and it hasn't been seen on a visible desktop yet.
        case unreachable
        /// Accessibility reached the window but no profile name was found on it.
        case unreadable
        /// The window's profile button shows only Chrome's managed-account badge ("Work" or "School"),
        /// which doesn't say which profile it is. Such windows are matched by name.
        case managedBadge
    }

    public private(set) var chromeProfileSources: [UInt32: ChromeProfileSource] = [:]
    /// Profiles read earlier, so a window keeps its profile after moving to a hidden desktop. Window IDs live as long as their window.
    private var rememberedProfiles: [UInt32: String] = [:]
    /// Chrome windows' bounds and titles on the last read, to find them again through AppleScript.
    private var chromeWindowFrames: [UInt32: (title: String, bounds: CGRect)] = [:]

    public init(skyLight: SkyLight) {
        self.skyLight = skyLight
        activeSpaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.activeSpaceChanged) }
        }
        appearanceObserver = WindowAppearanceObserver { [weak self] windowID in
            self?.onEvent?(.windowAppeared(windowID))
        }
        // Posted for every connect, disconnect and rearrangement, often several times per change.
        screenParametersObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.onEvent?(.displaysReconfigured) }
        }
    }

    // MARK: - Clock

    public func schedule(after delay: TimeInterval, _ action: @escaping @MainActor () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated { action() }
        }
    }

    // MARK: - Displays

    public func readDisplays() -> [WindowSystemDisplay] {
        let screens = Dictionary(
            NSScreen.screens.compactMap { screen in
                (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { ($0.uint32Value, screen) }
            },
            uniquingKeysWith: { first, _ in first }
        )
        return (skyLight.displayDesktops() ?? []).map { display in
            let displayID = Self.displayID(forSkyLightIdentifier: display.displayIdentifier)
            let desktops = display.desktops.compactMap { desktop -> WindowSystemDesktop? in
                let kind: DesktopKind
                switch desktop.kind {
                case .regular: kind = .regular
                case .fullscreen: kind = .fullscreen
                case .other: return nil
                }
                return WindowSystemDesktop(id: desktop.id, kind: kind, isCurrent: desktop.id == display.currentDesktopID)
            }
            return WindowSystemDisplay(
                id: displayID.flatMap(Self.uuidString) ?? display.displayIdentifier,
                hardwareID: displayID.flatMap(Self.hardwareID),
                name: displayID.flatMap { screens[$0]?.localizedName } ?? display.displayIdentifier,
                isBuiltIn: displayID.map { CGDisplayIsBuiltin($0) != 0 } ?? false,
                desktops: desktops,
                visibleFrame: displayID.flatMap { screens[$0] }.map(Self.visibleFrame) ?? .zero
            )
        }
    }

    /// The screen's visible frame, flipped from AppKit's bottom-left origin to the top-left origin windows use.
    private static func visibleFrame(of screen: NSScreen) -> WindowFrame {
        let mainHeight = NSScreen.screens.first?.frame.height ?? 0
        let frame = screen.visibleFrame
        return WindowFrame(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    }

    /// SkyLight names displays by UUID, except that the main display may appear as the literal "Main".
    private static func displayID(forSkyLightIdentifier identifier: String) -> CGDirectDisplayID? {
        if identifier == "Main" { return CGMainDisplayID() }
        return activeDisplayIDs().first { uuidString($0) == identifier }
    }

    private static func uuidString(_ displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }

    /// Vendor, model and serial number, the fallback identity for an external display WindowServer gives a new UUID.
    /// Nil without a serial number, since vendor and model alone can't tell two identical monitors apart.
    private static func hardwareID(_ displayID: CGDirectDisplayID) -> String? {
        let serial = CGDisplaySerialNumber(displayID)
        guard serial != 0 else { return nil }
        return "\(CGDisplayVendorNumber(displayID)):\(CGDisplayModelNumber(displayID)):\(serial)"
    }

    private static func activeDisplayIDs() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    // MARK: - Windows

    /// Accessibility only reaches windows on visible desktops, so the rest are judged from WindowServer's
    /// information. Apps keep untitled helper windows on their desktops (Chrome's fullscreen toolbar, find bar
    /// and tab-drag windows, for example); a real window has a title and is bigger than a toolbar.
    /// Titles are only visible with Screen Recording granted, which the Doctor checks.
    private static func looksStandard(title: String, bounds: CGRect?) -> Bool {
        guard let bounds, !title.isEmpty else { return false }
        return bounds.width >= 200 && bounds.height >= 150
    }

    public func readWindows() -> [WindowSystemWindow] {
        var desktopKinds: [UInt64: DesktopKind] = [:]
        for display in readDisplays() {
            for desktop in display.desktops { desktopKinds[desktop.id] = desktop.kind }
        }
        let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []

        var accessibilityByPID: [pid_t: [UInt32: AccessibilityWindow]] = [:]
        var windows: [WindowSystemWindow] = []
        var chromeScriptWindows: [ChromeScripting.ScriptWindow]?
        var profileSources: [UInt32: ChromeProfileSource] = [:]
        var chromeFrames: [UInt32: (title: String, bounds: CGRect)] = [:]
        for info in infos {
            guard (info[kCGWindowLayer as String] as? Int) == 0,
                  let number = info[kCGWindowNumber as String] as? NSNumber,
                  let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  let app = NSRunningApplication(processIdentifier: pid), app.activationPolicy == .regular,
                  let bundleID = app.bundleIdentifier
            else { continue }
            let windowID = number.uint32Value
            let desktops = (skyLight.desktopIDs(forWindow: windowID) ?? []).filter { desktopKinds[$0] != nil }
            guard !desktops.isEmpty else { continue }  // off every desktop: a helper or offscreen buffer

            if accessibilityByPID[pid] == nil { accessibilityByPID[pid] = Self.accessibilityWindows(pid: pid) }
            let accessibility = accessibilityByPID[pid]?[windowID]
            let desktopID = desktops.count == 1 ? desktops[0] : nil
            let title = (info[kCGWindowName as String] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? accessibility?.title ?? ""

            let bounds = (info[kCGWindowBounds as String] as? NSDictionary).flatMap { CGRect(dictionaryRepresentation: $0) }
            var profile = ChromeProfile.notChrome
            var name: String?
            if bundleID == Self.chromeBundleID {
                (profile, profileSources[windowID]) = chromeProfile(windowID, accessibility: accessibility)
                let bounds = bounds ?? .zero
                chromeFrames[windowID] = (title, bounds)
                if chromeScriptWindows == nil { chromeScriptWindows = ChromeScripting.windows() ?? [] }
                name = chromeScriptWindows?.first { $0.title == title && $0.bounds == bounds }?.givenName
            }

            windows.append(WindowSystemWindow(
                id: windowID,
                bundleID: bundleID,
                appName: app.localizedName ?? bundleID,
                title: title,
                desktopID: desktopID,
                isFullscreen: desktopID.map { desktopKinds[$0] == .fullscreen } ?? false,
                chromeProfile: profile,
                isStandard: accessibility.map { $0.subrole == kAXStandardWindowSubrole as String }
                    ?? Self.looksStandard(title: title, bounds: bounds),
                name: name,
                frame: bounds.map { WindowFrame(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) }
            ))
        }
        chromeProfileSources = profileSources
        chromeWindowFrames = chromeFrames
        rememberedProfiles = rememberedProfiles.filter { profileSources[$0.key] != nil }
        return windows
    }

    /// Reads a Chrome window's profile through Accessibility, or remembers it from when the window was last visible.
    /// The toolbar button text Accessibility shows for a Chrome window on a visible desktop, for the Doctor.
    public func chromeButtonTexts(_ windowID: UInt32) -> [String]? {
        guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: Self.chromeBundleID).first?.processIdentifier,
              let element = Self.accessibilityWindows(pid: pid)[windowID]?.element
        else { return nil }
        return ChromeProfileReader.buttonTexts(of: element)
    }

    private func chromeProfile(_ windowID: UInt32, accessibility: AccessibilityWindow?) -> (ChromeProfile, ChromeProfileSource) {
        if let accessibility {
            switch ChromeProfileReader.profile(of: accessibility.element) {
            case .known(let profile)?:
                rememberedProfiles[windowID] = profile
                return (.known(profile), .read)
            case .unknown?:
                return (.unknown, .managedBadge)
            default:
                break
            }
            return (rememberedProfiles[windowID].map(ChromeProfile.known) ?? .unknown, .unreadable)
        }
        if let profile = rememberedProfiles[windowID] { return (.known(profile), .remembered) }
        return (.unknown, .unreachable)
    }

    // MARK: - Actions

    /// How long a bridged move gets to land before it counts as failed.
    private static let moveSettleTimeout: TimeInterval = 1

    /// The bridged move is asynchronous, so this polls until the window is on the target desktop.
    public func moveWindow(_ windowID: UInt32, toDesktop desktopID: UInt64) -> Bool {
        guard skyLight.moveWindow(windowID, toDesktop: desktopID) else { return false }
        let deadline = Date().addingTimeInterval(Self.moveSettleTimeout)
        repeat {
            if skyLight.desktopIDs(forWindow: windowID) == [desktopID] { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        } while Date() < deadline
        return false
    }

    /// How long the fullscreen animation gets to finish before the change counts as failed.
    private static let fullscreenSettleTimeout: TimeInterval = 3

    /// Sets Accessibility's `AXFullScreen`, then polls until the window sits on a desktop of the new kind.
    /// Accessibility only reaches windows on visible desktops, so a window on a hidden one can't be changed.
    public func setFullscreen(_ windowID: UInt32, _ isFullscreen: Bool) -> Bool {
        guard let info = Self.windowInfo(windowID),
              let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let element = Self.element(of: windowID, ownedBy: pid)
        else { return false }
        func settled() -> Bool {
            guard let desktops = skyLight.desktopIDs(forWindow: windowID), desktops.count == 1 else { return false }
            let kind = (skyLight.displayDesktops() ?? []).lazy.flatMap(\.desktops).first { $0.id == desktops[0] }?.kind
            return kind == (isFullscreen ? .fullscreen : .regular)
        }
        if settled() { return true }
        guard AXUIElementSetAttributeValue(element, "AXFullScreen" as CFString, (isFullscreen ? kCFBooleanTrue : kCFBooleanFalse)) == .success
        else { return false }
        let deadline = Date().addingTimeInterval(Self.fullscreenSettleTimeout)
        repeat {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            if settled() {
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))  // let the animation finish before the next step
                return true
            }
        } while Date() < deadline
        return false
    }

    /// A window's Accessibility element wherever it is. An app's window list only covers the desktop being shown,
    /// so a window on another desktop (a fullscreen window Restore has to take out and put back, say) is reached
    /// through `PrivateAccessibility.windowsOnEveryDesktop` instead.
    private static func element(of windowID: UInt32, ownedBy pid: pid_t) -> AXUIElement? {
        accessibilityWindows(pid: pid)[windowID]?.element
            ?? PrivateAccessibility.windowsOnEveryDesktop(pid: pid, wanted: [windowID])[windowID]
    }

    /// Finds the window through Chrome's AppleScript by its title and bounds, since AppleScript window IDs aren't WindowServer IDs.
    public func setChromeWindowName(_ windowID: UInt32, to name: String) -> WindowNamingResult {
        guard let frame = chromeWindowFrames[windowID] else { return .failed("Space Maker hasn't seen that Chrome window.") }
        return ChromeScripting.setName(name, ofWindowTitled: frame.title, bounds: frame.bounds)
    }

    /// Whether Space Maker may automate Chrome, for the Doctor. Never prompts.
    public static func chromeAutomationStatus() -> (granted: Bool?, summary: String) {
        switch ChromeScripting.permission(ask: false) {
        case .granted: (true, "Space Maker may name Chrome windows.")
        case .denied: (false, ChromeScripting.deniedReason)
        case .notAsked: (nil, "Not asked yet; Save asks the first time it needs to name a Chrome window.")
        case .chromeNotRunning: (nil, "Google Chrome isn't running.")
        case .other(let status): (false, "macOS couldn't check Automation permission for Google Chrome (error \(status)).")
        }
    }

    private struct AccessibilityWindow {
        let element: AXUIElement
        let title: String?
        let subrole: String?
    }

    private static func accessibilityWindows(pid: pid_t) -> [UInt32: AccessibilityWindow] {
        guard AXIsProcessTrusted() else { return [:] }
        let app = AXUIElementCreateApplication(pid)
        guard let elements: [AXUIElement] = AX.value(app, kAXWindowsAttribute) else { return [:] }
        var result: [UInt32: AccessibilityWindow] = [:]
        for element in elements {
            guard let id = PrivateAccessibility.windowID(of: element) else { continue }
            result[id] = AccessibilityWindow(element: element, title: AX.value(element, kAXTitleAttribute), subrole: AX.value(element, kAXSubroleAttribute))
        }
        return result
    }

    /// Chrome profile reading, for the Doctor: why a Chrome window's profile might be unknown.
    public static var chromeProfileLimitations: [String] {
        var notes: [String] = []
        if !AXIsProcessTrusted() { notes.append("Accessibility isn't granted, so no Chrome window can be inspected.") }
        if !PrivateAccessibility.canMapWindows { notes.append("`\(PrivateAccessibility.windowIDSymbol)` is missing, so Accessibility windows can't be matched to window IDs.") }
        notes.append("Accessibility only reaches windows on desktops currently visible. A Chrome window on another desktop keeps the profile last read while it was visible; one never seen on a visible desktop reports an unknown profile.")
        return notes
    }
}

/// Reads a Chrome window's profile from its toolbar avatar button.
///
/// The button's accessible text contains the profile's name, so the window's buttons are matched
/// against the profile names in Chrome's `Local State`. Unverified on the user's Mac until the live demo.
enum ChromeProfileReader {
    private static let maxDepth = 10

    static func profile(of window: AXUIElement) -> ChromeProfile? {
        let names = profileNames()
        if names.count == 1 { return .known(names[0]) }
        guard !names.isEmpty else { return nil }
        // A managed (Google Workspace) profile's button shows Chrome's "Work" or "School" badge instead of its
        // name, so that text says nothing about which profile it is, even when a profile happens to be named "Work".
        let badges: Set<String> = hasManagedProfile() ? ["work", "school"] : []
        var found = Set<String>()
        var sawBadge = false
        collectButtonText(window, depth: 0) { text in
            guard !badges.contains(text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) else {
                sawBadge = true
                return
            }
            for name in names where text.localizedCaseInsensitiveContains(name) { found.insert(name) }
        }
        if found.isEmpty, sawBadge { return .unknown }
        // A profile name contained in another ("Work" in "Work 2") prefers the longest match.
        let longest = found.max { $0.count < $1.count }
        guard let longest, found.allSatisfy({ longest.localizedCaseInsensitiveContains($0) }) else { return nil }
        return .known(longest)
    }

    /// Every distinct piece of toolbar button text in a window, for the Doctor's report.
    static func buttonTexts(of window: AXUIElement) -> [String] {
        var texts: [String] = []
        collectButtonText(window, depth: 0) { if !texts.contains($0) { texts.append($0) } }
        return texts
    }

    private static func collectButtonText(_ element: AXUIElement, depth: Int, _ visit: (String) -> Void) {
        guard depth < maxDepth else { return }
        let role: String? = AX.value(element, kAXRoleAttribute)
        if role == kAXButtonRole as String || role == kAXPopUpButtonRole as String || role == kAXMenuButtonRole as String {
            for attribute in [kAXDescriptionAttribute, kAXTitleAttribute, kAXHelpAttribute] {
                if let text: String = AX.value(element, attribute), !text.isEmpty { visit(text) }
            }
            return
        }
        // Skip the web page itself: its buttons belong to websites, not Chrome.
        if role == "AXWebArea" { return }
        for child in AX.value(element, kAXChildrenAttribute) as [AXUIElement]? ?? [] {
            collectButtonText(child, depth: depth + 1, visit)
        }
    }

    /// The profile names Chrome lists in `Local State`.
    static func profileNames() -> [String] {
        profiles().compactMap { $0["name"] as? String }.sorted()
    }

    /// Whether any profile is signed in to a managed (Google Workspace) account, whose button shows a badge.
    static func hasManagedProfile() -> Bool {
        profiles().contains { profile in
            (profile["is_managed"] as? Int) == 1
                || (profile["hosted_domain"] as? String).map { !$0.isEmpty && $0 != "NO_HOSTED_DOMAIN" } == true
        }
    }

    private static func profiles() -> [[String: Any]] {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/Local State")
        guard let data = try? Data(contentsOf: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cache = (root["profile"] as? [String: Any])?["info_cache"] as? [String: Any]
        else { return [] }
        return cache.values.compactMap { $0 as? [String: Any] }
    }
}

/// Small typed wrappers over the Accessibility C API.
enum AX {
    static func value<T>(_ element: AXUIElement, _ attribute: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? T
    }
}

// MARK: - Focus and Pin mirrors

extension MacWindowSystem {
    public func readFrontmostWindow() -> UInt32? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        guard let window: AXUIElement = AX.value(element, kAXFocusedWindowAttribute) else { return nil }
        return PrivateAccessibility.windowID(of: window)
    }

    public func focusWindow(_ windowID: UInt32) {
        guard let info = Self.windowInfo(windowID),
              let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value
        else { return }
        if skyLight.focusWindow(windowID, ownedBy: pid) { return }
        // Fallback: activating the app switches to a desktop with one of its windows, maybe not this one.
        NSRunningApplication(processIdentifier: pid)?.activate()
        if let element = Self.accessibilityWindows(pid: pid)[windowID]?.element {
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
        }
    }

    /// Sets the frame through Accessibility, which only reaches windows on desktops currently showing.
    public func setFrame(_ windowID: UInt32, to frame: WindowFrame) -> Bool {
        guard let pid = (Self.windowInfo(windowID)?[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
              let element = Self.element(of: windowID, ownedBy: pid)
        else { return false }
        var origin = CGPoint(x: frame.x, y: frame.y)
        var size = CGSize(width: frame.width, height: frame.height)
        guard let position = AXValueCreate(.cgPoint, &origin), let extent = AXValueCreate(.cgSize, &size) else { return false }
        // Size, position, then size again: a window moving to a smaller display may be clamped by its old position.
        AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, extent)
        let moved = AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, position)
        let sized = AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, extent)
        return moved == .success && sized == .success
    }

    public func showPinMirror(of windowID: UInt32) {
        if let mirror = mirrors[windowID] {
            mirror.show()
            return
        }
        let bounds = (Self.windowInfo(windowID)?[kCGWindowBounds as String] as? NSDictionary)
            .flatMap { CGRect(dictionaryRepresentation: $0) } ?? .zero
        let mirror = PinMirror(windowID: windowID, sourceFrame: bounds) { [weak self] in
            self?.onEvent?(.pinClicked(windowID))
        }
        mirror.onCaptureStopped = { [weak self] in
            // A stream also stops when Screen Recording is revoked; only a vanished window is a close.
            if Self.windowInfo(windowID) == nil { self?.onEvent?(.windowClosed(windowID)) }
        }
        mirrors[windowID] = mirror
        mirror.show()
    }

    public func hidePinMirror(of windowID: UInt32) {
        mirrors[windowID]?.hide()
    }

    public func stopPinMirror(of windowID: UInt32) {
        mirrors.removeValue(forKey: windowID)?.stop()
    }

    private static func windowInfo(_ windowID: UInt32) -> [String: Any]? {
        (CGWindowListCopyWindowInfo(.optionIncludingWindow, windowID) as? [[String: Any]])?.first
    }
}
