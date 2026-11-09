import AppKit
import CoreGraphics
import Foundation

/// Chrome's AppleScript interface, used for a window's `given name`: Chrome shows it as the window's title
/// and session restore keeps it across a relaunch (spec, Further Notes). Needs Automation permission for Chrome.
@MainActor
enum ChromeScripting {
    enum Permission: Equatable {
        case granted
        case denied
        /// The user hasn't been asked yet; the first naming asks.
        case notAsked
        case chromeNotRunning
        case other(OSStatus)
    }

    /// One Chrome window as AppleScript sees it.
    struct ScriptWindow {
        let givenName: String?
        let title: String
        /// Global coordinates, top-left origin, as CoreGraphics reports window bounds.
        let bounds: CGRect
    }

    static var isChromeRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: MacWindowSystem.chromeBundleID).isEmpty
    }

    /// Whether Space Maker may send Chrome Apple Events. With `ask`, macOS prompts the user if they haven't
    /// decided yet, and this blocks until they answer.
    static func permission(ask: Bool) -> Permission {
        guard isChromeRunning else { return .chromeNotRunning }
        let target = NSAppleEventDescriptor(bundleIdentifier: MacWindowSystem.chromeBundleID)
        guard let address = target.aeDesc else { return .other(OSStatus(paramErr)) }
        let status = AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, ask)
        switch status {
        case noErr: return .granted
        case OSStatus(errAEEventNotPermitted): return .denied
        case OSStatus(errAEEventWouldRequireUserConsent): return .notAsked
        case OSStatus(procNotFound): return .chromeNotRunning
        default: return .other(status)
        }
    }

    static let deniedReason = "Space Maker isn't allowed to automate Google Chrome. Allow it under System Settings → Privacy & Security → Automation → Space Maker → Google Chrome, then Save again."

    /// Every Chrome window's given name, title and bounds, or nil if Chrome can't be asked without prompting.
    static func windows() -> [ScriptWindow]? {
        Log.timed(Log.adapter, "Chrome AppleScript window list") { windowsNow() }
    }

    private static func windowsNow() -> [ScriptWindow]? {
        guard permission(ask: false) == .granted else { return nil }
        let source = """
        tell application id "\(MacWindowSystem.chromeBundleID)"
            set found to {}
            repeat with w in windows
                set end of found to {given name of w, name of w, bounds of w}
            end repeat
            return found
        end tell
        """
        guard let list = run(source).descriptor, list.numberOfItems > 0 else { return [] }
        return (1...list.numberOfItems).compactMap { index in
            guard let item = list.atIndex(index), item.numberOfItems == 3,
                  let bounds = item.atIndex(3), bounds.numberOfItems == 4
            else { return nil }
            let edges = (1...4).map { CGFloat(bounds.atIndex($0)?.int32Value ?? 0) }
            let givenName = item.atIndex(1)?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
            return ScriptWindow(
                givenName: givenName, title: item.atIndex(2)?.stringValue ?? "",
                bounds: CGRect(x: edges[0], y: edges[1], width: edges[2] - edges[0], height: edges[3] - edges[1])
            )
        }
    }

    /// Sets the given name of the Chrome window with this title and bounds, asking for permission if needed.
    static func setName(_ name: String, ofWindowTitled title: String, bounds: CGRect) -> WindowNamingResult {
        switch permission(ask: true) {
        case .granted: break
        case .denied: return .denied(deniedReason)
        case .notAsked: return .denied("Space Maker asked for permission to automate Google Chrome and is still waiting for an answer.")
        case .chromeNotRunning: return .failed("Google Chrome isn't running.")
        case .other(let status): return .failed("macOS couldn't check Automation permission for Google Chrome (error \(status)).")
        }
        let source = """
        tell application id "\(MacWindowSystem.chromeBundleID)"
            repeat with w in windows
                if name of w is \(literal(title)) and (bounds of w) is {\(Int(bounds.minX)), \(Int(bounds.minY)), \(Int(bounds.maxX)), \(Int(bounds.maxY))} then
                    set given name of w to \(literal(name))
                    return "named"
                end if
            end repeat
            return "missing"
        end tell
        """
        let outcome = run(source)
        if let error = outcome.error { return .failed("Chrome's AppleScript failed: \(error)") }
        return outcome.descriptor?.stringValue == "named"
            ? .named
            : .failed("Chrome's AppleScript couldn't find the window titled “\(title)”.")
    }

    private static func run(_ source: String) -> (descriptor: NSAppleEventDescriptor?, error: String?) {
        var errorInfo: NSDictionary?
        let descriptor = NSAppleScript(source: source)?.executeAndReturnError(&errorInfo)
        let error = errorInfo.map { ($0[NSAppleScript.errorMessage] as? String) ?? "\($0)" }
        return (descriptor, error)
    }

    /// An AppleScript string literal.
    private static func literal(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
