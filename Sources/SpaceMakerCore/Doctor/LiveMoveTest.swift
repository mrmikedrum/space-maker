import Foundation

/// Moves a window owned by a separate helper process to another regular desktop and back,
/// verifying each move with SkyLight. This is the check that tells the user whether the
/// SIP-on bridged move works on their macOS build.
@MainActor
struct LiveMoveTest {
    let skyLight: SkyLight
    let helperExecutable: URL

    private let settleTimeout: TimeInterval = 3

    func run() -> CheckOutcome {
        guard skyLight.canReadDesktops else {
            return skipped("SkyLight's read-only desktop calls are missing (see \(StandardDoctor.symbolsTitle)).")
        }
        guard skyLight.canMoveWindows else {
            return CheckOutcome(
                .fail(suspectedCause: "The bridged move operation isn't available on this macOS build (see \(StandardDoctor.symbolsTitle)). yabai v7.1.25 confirms it on Tahoe 26.4+; upgrading macOS is the likely fix."),
                summary: "Can't issue a move: the bridged move operation is missing."
            )
        }
        guard FileManager.default.isExecutableFile(atPath: helperExecutable.path) else {
            return skipped("The move-test helper wasn't found at \(helperExecutable.path). Rebuild with scripts/build-app.sh.")
        }

        let helper: HelperProcess
        do {
            helper = try HelperProcess.launch(helperExecutable)
        } catch {
            return skipped("The move-test helper couldn't start: \(error.localizedDescription)")
        }
        defer { helper.stop() }

        var details = ["Helper window ID: \(helper.windowID)"]

        guard let origin = waitForSingleDesktop(of: helper.windowID, matching: { _ in true }) else {
            return skipped("The helper's window never appeared on a desktop within \(Int(settleTimeout))s.")
        }
        guard let target = otherRegularDesktop(than: origin) else {
            return skipped("Only one regular desktop exists. Add a second desktop in Mission Control and re-run the Doctor.")
        }
        details.append("Window starts on desktop \(origin); target desktop \(target).")

        let there = move(helper.windowID, to: target)
        details.append(there.detail)
        let back = move(helper.windowID, to: origin)
        details.append(back.detail)

        guard there.landed, back.landed else {
            return CheckOutcome(
                .fail(suspectedCause: "WindowServer accepted the bridged move but ignored it. This method is confirmed on Tahoe 26.4+ and unconfirmed on macOS 15; upgrading macOS is the likely fix. If already on 26.4.1–26.6, moves into an empty desktop are a known failure (yabai #2789): put any window on the target desktop and retry."),
                summary: "The window did not move\(there.landed ? " back" : "").",
                details: details
            )
        }
        return CheckOutcome(.pass, summary: "Moved the helper's window to desktop \(target) and back.", details: details)
    }

    private func move(_ windowID: UInt32, to desktop: UInt64) -> (landed: Bool, detail: String) {
        let start = Date()
        guard skyLight.moveWindow(windowID, toDesktop: desktop) else {
            return (false, "Move to \(desktop): the operation could not be created.")
        }
        let landed = waitForSingleDesktop(of: windowID, matching: { $0 == desktop }) != nil
        let elapsed = Int(Date().timeIntervalSince(start) * 1000)
        let now = skyLight.desktopIDs(forWindow: windowID).map { $0.map(String.init).joined(separator: ", ") } ?? "unknown"
        return (landed, "Move to \(desktop): \(landed ? "landed after \(elapsed) ms" : "did not land within \(Int(settleTimeout))s; window is on \(now)").")
    }

    /// Polls until the window is on exactly one desktop that satisfies `matching`.
    private func waitForSingleDesktop(of windowID: UInt32, matching: (UInt64) -> Bool) -> UInt64? {
        let deadline = Date().addingTimeInterval(settleTimeout)
        repeat {
            if let ids = skyLight.desktopIDs(forWindow: windowID), ids.count == 1, matching(ids[0]) {
                return ids[0]
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return nil
    }

    /// Prefers another regular desktop on the same display, then any other display's.
    private func otherRegularDesktop(than origin: UInt64) -> UInt64? {
        let displays = skyLight.displayDesktops() ?? []
        let home = displays.first { $0.desktops.contains { $0.id == origin } }
        let sameDisplay = home?.regularDesktopIDs.filter { $0 != origin } ?? []
        let elsewhere = displays.filter { $0.displayIdentifier != home?.displayIdentifier }.flatMap(\.regularDesktopIDs)
        return (sameDisplay + elsewhere).first
    }

    private func skipped(_ reason: String) -> CheckOutcome {
        CheckOutcome(.skipped(reason: reason), summary: "Not run.")
    }
}

/// The move-test helper: a separate process, so its window belongs to "another app".
/// It prints its window ID on stdout and exits when its stdin closes.
private final class HelperProcess {
    let windowID: UInt32
    private let process: Process
    private let stdin: Pipe

    private init(windowID: UInt32, process: Process, stdin: Pipe) {
        self.windowID = windowID
        self.process = process
        self.stdin = stdin
    }

    struct LaunchError: LocalizedError {
        let errorDescription: String?
    }

    static func launch(_ executable: URL) throws -> HelperProcess {
        let process = Process()
        process.executableURL = executable
        let stdout = Pipe()
        let stdin = Pipe()
        process.standardOutput = stdout
        process.standardInput = stdin
        try process.run()

        let line = FirstLineReader(stdout.fileHandleForReading)
        guard let text = line.wait(timeout: 5), let windowID = UInt32(text) else {
            process.terminate()
            throw LaunchError(errorDescription: "it didn't report a window ID within 5s")
        }
        return HelperProcess(windowID: windowID, process: process, stdin: stdin)
    }

    func stop() {
        try? stdin.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        process.waitUntilExit()
    }
}

/// Reads the first line from a pipe on a background thread, with a timeout.
private final class FirstLineReader: @unchecked Sendable {
    private let done = DispatchSemaphore(value: 0)
    private var line: String?

    init(_ handle: FileHandle) {
        Thread.detachNewThread { [self] in
            var data = Data()
            while true {
                let chunk = handle.availableData
                if chunk.isEmpty { break }
                data.append(chunk)
                if data.contains(UInt8(ascii: "\n")) { break }
            }
            line = String(decoding: data, as: UTF8.self).split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) }
            done.signal()
        }
    }

    func wait(timeout: TimeInterval) -> String? {
        done.wait(timeout: .now() + timeout) == .success ? line : nil
    }
}
