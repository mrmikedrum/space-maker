import AppKit
import ApplicationServices
import Foundation

/// The Doctor as Space Maker ships it: real checks against this Mac.
@MainActor
public enum StandardDoctor {
    public static let liveMoveTitle = "Live move test"

    public static func make(skyLight: SkyLight, helperExecutable: URL, logsDirectory: URL) -> Doctor {
        Doctor(
            logsDirectory: logsDirectory,
            environment: environment(),
            checks: [
                DoctorCheck(title: "Permissions") { permissions() },
                DoctorCheck(title: "Private SkyLight symbols") { symbols(skyLight) },
                DoctorCheck(title: "Display and desktop enumeration") { enumeration(skyLight) },
                DoctorCheck(title: liveMoveTitle) { LiveMoveTest(skyLight: skyLight, helperExecutable: helperExecutable).run() },
            ],
            verdict: verdict
        )
    }

    public static var defaultLogsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SpaceMaker")
    }

    static func verdict(_ results: [CheckResult]) -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersionString.replacingOccurrences(of: "Version ", with: "")
        let failures = results.filter(\.failed).map(\.title)
        let move: String = switch results.first(where: { $0.title == liveMoveTitle })?.outcome {
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
            ("SIP", run("/usr/bin/csrutil", ["status"])?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "unknown"),
            ("Space Maker", "\(version) at \(bundle.bundlePath)"),
            ("Bundle identifier", bundle.bundleIdentifier ?? "none (not running as an app bundle; permissions belong to the parent process)"),
        ]
    }

    // MARK: - Checks

    static func permissions() -> CheckResult {
        let accessibility = AXIsProcessTrusted()
        let screenRecording = CGPreflightScreenCaptureAccess()
        let details = [
            "Accessibility: \(accessibility ? "granted" : "NOT granted")",
            "Screen Recording: \(screenRecording ? "granted" : "NOT granted")",
        ]
        let missing = [accessibility ? nil : "Accessibility", screenRecording ? nil : "Screen Recording"].compactMap { $0 }
        guard missing.isEmpty else {
            return CheckResult(
                title: "Permissions",
                outcome: .fail(suspectedCause: "Space Maker hasn't been granted \(missing.joined(separator: " and ")). Add Space Maker.app under System Settings → Privacy & Security → \(missing.joined(separator: " / ")), then re-run the Doctor. Moving windows between desktops does not need these; later features do."),
                summary: "Missing \(missing.joined(separator: " and ")).",
                details: details
            )
        }
        return CheckResult(title: "Permissions", outcome: .pass, summary: "Accessibility and Screen Recording granted.", details: details)
    }

    static func symbols(_ skyLight: SkyLight) -> CheckResult {
        let details = skyLight.symbols.map { "\($0.isPresent ? "found" : "MISSING"): `\($0.name)`" }
        let missing = skyLight.missingSymbols
        guard missing.isEmpty else {
            return CheckResult(
                title: "Private SkyLight symbols",
                outcome: .fail(suspectedCause: "This macOS build renamed or removed private SkyLight API that Space Maker relies on. Compare against the current yabai source to find the replacement."),
                summary: "\(missing.count) of \(skyLight.symbols.count) missing.",
                details: details
            )
        }
        return CheckResult(title: "Private SkyLight symbols", outcome: .pass, summary: "All \(skyLight.symbols.count) found.", details: details)
    }

    static func enumeration(_ skyLight: SkyLight) -> CheckResult {
        guard let displays = skyLight.displayDesktops(), !displays.isEmpty else {
            return CheckResult(
                title: "Display and desktop enumeration",
                outcome: .fail(suspectedCause: "SLSCopyManagedDisplaySpaces is missing or returned nothing; its result format may have changed."),
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
        let regular = displays.reduce(0) { $0 + $1.desktops.filter { $0.kind == .regular }.count }
        return CheckResult(
            title: "Display and desktop enumeration",
            outcome: .pass,
            summary: "\(displays.count) display(s), \(regular) regular desktop(s).",
            details: details
        )
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

    private static func run(_ path: String, _ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
