import AppKit
import ApplicationServices
import Foundation

/// The Doctor as Space Maker ships it: real checks against this Mac.
@MainActor
public enum StandardDoctor {
    static let symbolsTitle = "Private macOS symbols"
    static let liveMoveTitle = "Live move test"
    /// Pins depend on this check: when it doesn't pass, Pins are disabled.
    public static let screenCaptureTitle = "Screen capture"

    public static func make(
        skyLight: SkyLight,
        windowSystem: MacWindowSystem? = nil,
        helperExecutable: URL,
        logsDirectory: URL
    ) -> Doctor {
        let windowSystem = windowSystem ?? MacWindowSystem(skyLight: skyLight)
        return Doctor(
            logsDirectory: logsDirectory,
            environment: environment(),
            checks: [
                DoctorCheck(title: "Permissions") { permissions() },
                DoctorCheck(title: symbolsTitle) { symbols(skyLight) },
                DoctorCheck(title: "Display and desktop enumeration") { enumeration(skyLight) },
                DoctorCheck(title: "Chrome profiles") { chromeProfiles(windowSystem) },
                DoctorCheck(title: screenCaptureTitle) { await ScreenCaptureCheck.run() },
                DoctorCheck(title: "Chrome Automation") { chromeAutomation() },
                DoctorCheck(title: liveMoveTitle) { LiveMoveTest(skyLight: skyLight, helperExecutable: helperExecutable).run() },
            ],
            verdict: verdict
        )
    }

    public static var defaultLogsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SpaceMaker")
    }

    /// Why moving windows doesn't work, if the live move test failed. Restore and `move_window` depend on it.
    public static func moveFailure(in results: [CheckResult]) -> String? {
        guard let result = results.first(where: { $0.title == liveMoveTitle }),
              case .fail(let cause) = result.status
        else { return nil }
        return "\(result.outcome.summary) Suspected cause: \(cause)"
    }

    static func verdict(_ results: [CheckResult]) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: "")
        let failures = results.filter(\.failed).map(\.title)
        let move: String = switch results.first(where: { $0.title == liveMoveTitle })?.status {
        case .pass: "Moving another app's window between desktops WORKS on macOS \(os)."
        case .fail: "Moving another app's window between desktops FAILS on macOS \(os)."
        case .skipped, nil: "Moving windows between desktops was NOT TESTED on macOS \(os)."
        }
        return failures.isEmpty ? "\(move) All checks passed." : "\(move) Failed: \(failures.joined(separator: ", "))."
    }

    // MARK: - Environment

    static func environment() -> [(String, String)] {
        let bundle = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unbundled"
        return [
            ("macOS", ProcessInfo.processInfo.operatingSystemVersionString),
            ("Hardware", sysctlString("hw.model") ?? "unknown"),
            ("SIP", runCommand("/usr/bin/csrutil", ["status"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"),
            ("Space Maker", "\(version) at \(bundle.bundlePath)"),
            ("Bundle identifier", bundle.bundleIdentifier ?? "none (not running as an app bundle; permissions belong to the parent process)"),
        ]
    }

    // MARK: - Checks

    static func permissions() -> CheckOutcome {
        let accessibility = AXIsProcessTrusted()
        let screenRecording = CGPreflightScreenCaptureAccess()
        let details = [
            "Accessibility: \(accessibility ? "granted" : "NOT granted")",
            "Screen Recording: \(screenRecording ? "granted" : "NOT granted")",
        ]
        let missing = [accessibility ? nil : "Accessibility", screenRecording ? nil : "Screen Recording"].compactMap { $0 }
        guard missing.isEmpty else {
            return CheckOutcome(
                .fail(suspectedCause: "Space Maker hasn't been granted \(missing.joined(separator: " and ")). Add Space Maker.app under System Settings → Privacy & Security → \(missing.joined(separator: " / ")), then re-run the Doctor. Moving windows between desktops does not need these; later features do."),
                summary: "Missing \(missing.joined(separator: " and ")).",
                details: details
            )
        }
        return CheckOutcome(.pass, summary: "Accessibility and Screen Recording granted.", details: details)
    }

    static func symbols(_ skyLight: SkyLight) -> CheckOutcome {
        let accessibility = [
            (PrivateAccessibility.windowIDSymbol, PrivateAccessibility.canMapWindows),
            (PrivateAccessibility.remoteTokenSymbol, PrivateAccessibility.canReachHiddenWindows),
        ]
        let details = skyLight.symbols.map { "\($0.isPresent ? "found" : "MISSING"): `\($0.name)`" }
            + accessibility.map { "\($0.1 ? "found" : "MISSING"): `\($0.0)` (Accessibility)" }
        let missing = skyLight.missingSymbols + accessibility.filter { !$0.1 }.map(\.0)
        guard missing.isEmpty else {
            return CheckOutcome(
                .fail(suspectedCause: "This macOS build renamed or removed private SkyLight API that Space Maker relies on. Compare against the current yabai source to find the replacement."),
                summary: "\(missing.count) of \(details.count) missing.",
                details: details
            )
        }
        return CheckOutcome(.pass, summary: "All \(details.count) found.", details: details)
    }

    static func enumeration(_ skyLight: SkyLight) -> CheckOutcome {
        guard let displays = skyLight.displayDesktops(), !displays.isEmpty else {
            return CheckOutcome(
                .fail(suspectedCause: "SLSCopyManagedDisplaySpaces is missing or returned nothing; its result format may have changed."),
                summary: "Could not read displays and desktops."
            )
        }
        let activeDisplays = activeDisplayCount()
        var details = displays.map { display in
            let desktops = display.desktops.map { desktop in
                let kind = switch desktop.kind {
                case .regular: "desktop"
                case .fullscreen: "fullscreen"
                case .other(let type): "type \(type)"
                }
                return "\(desktop.id) (\(kind)\(desktop.id == display.currentDesktopID ? ", current" : ""))"
            }
            return "Display `\(display.displayIdentifier)`: \(desktops.joined(separator: ", "))"
        }
        details.append("CoreGraphics reports \(activeDisplays) active display(s).")
        let regular = displays.reduce(0) { $0 + $1.regularDesktopIDs.count }
        return CheckOutcome(
            .pass,
            summary: "\(displays.count) display(s), \(regular) regular desktop(s).",
            details: details
        )
    }

    /// Fails only when Accessibility reached a Chrome window and still found no profile, which means Chrome changed.
    /// A window on a hidden desktop that hasn't been seen yet is a finding, not a failure: Save names it, and it's matched by name.
    static func chromeProfiles(_ windowSystem: MacWindowSystem) -> CheckOutcome {
        let chrome = windowSystem.readWindows().filter { $0.bundleID == MacWindowSystem.chromeBundleID && $0.isStandard }
        guard !chrome.isEmpty else {
            return CheckOutcome(.skipped(reason: "Chrome has no windows open."), summary: "No Chrome windows to read.")
        }
        let sources = windowSystem.chromeProfileSources
        var details = chrome.map { window in
            let profile = if case .known(let name) = window.chromeProfile { name } else { "UNKNOWN" }
            let source = switch sources[window.id] {
            case .read: "read now"
            case .remembered: "remembered; on a hidden desktop"
            case .unreachable: "on a hidden desktop, not seen yet"
            case .unreadable: "Accessibility reached the window but found no profile name"
            case .managedBadge: "managed profile: Chrome shows only a Work/School badge, so it's matched by name"
            case nil: "not inspected"
            }
            let buttons = windowSystem.chromeButtonTexts(window.id).map { "; toolbar buttons: " + $0.map { "“\($0)”" }.joined(separator: ", ") } ?? ""
            return "Window \(window.id) \"\(window.title)\": profile \(profile) (\(source))\(buttons)"
        }
        details.append("Chrome's profiles: " + ChromeProfileReader.profileNames().map { "“\($0)”" }.joined(separator: ", "))
        let unreadable = chrome.filter { sources[$0.id] == .unreadable }.count
        let unreachable = chrome.filter { $0.chromeProfile == .unknown && sources[$0.id] != .unreadable }.count
        if unreadable > 0 {
            details += MacWindowSystem.chromeProfileLimitations.map { "Possible reason: \($0)" }
            return CheckOutcome(
                .fail(suspectedCause: "Space Maker reads a Chrome window's profile from its toolbar avatar button through Accessibility, matching it against the profile names in Chrome's `Local State`. Accessibility reached these windows but found no profile name, so Chrome probably changed the avatar button's accessible text or the profile names moved. Look at `ChromeProfileReader` in `SpaceMakerCore/MacOS/MacWindowSystem.swift`."),
                summary: "\(unreadable) of \(chrome.count) visible Chrome window(s) show no readable profile.",
                details: details
            )
        }
        let summary = unreachable == 0
            ? "Know the profile of all \(chrome.count) Chrome window(s)."
            : "Know the profile of \(chrome.count - unreachable) of \(chrome.count) Chrome window(s). The other \(unreachable) are on hidden desktops Accessibility can't reach until they're shown; Save names them so they're matched by name instead."
        return CheckOutcome(.pass, summary: summary, details: details)
    }

    /// Save names look-alike Chrome windows through AppleScript, which needs Automation permission for Chrome.
    static func chromeAutomation() -> CheckOutcome {
        let status = MacWindowSystem.chromeAutomationStatus()
        switch status.granted {
        case true?:
            return CheckOutcome(.pass, summary: status.summary)
        case false?:
            return CheckOutcome(
                .fail(suspectedCause: "Without Automation permission, Save can't name Chrome windows that share a profile and fullscreen state, so they may be mixed up after Chrome relaunches. Save itself still works."),
                summary: status.summary
            )
        case nil:
            return CheckOutcome(.skipped(reason: status.summary), summary: "Not checked.")
        }
    }

    // MARK: - Helpers

    private static func activeDisplayCount() -> Int {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)
        return Int(count)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        return String(decoding: buffer.prefix(while: { $0 != 0 }).map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    private static func runCommand(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return nil }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()  // drain before waiting, or a full pipe deadlocks
        process.waitUntilExit()
        return String(data: output, encoding: .utf8)
    }
}
