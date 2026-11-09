import AppKit
@preconcurrency import ScreenCaptureKit

/// The Doctor's check that ScreenCaptureKit can capture a single window, as Pin mirrors do.
@MainActor
enum ScreenCaptureCheck {
    private static let timeout: TimeInterval = 5

    static func run() -> CheckOutcome {
        guard CGPreflightScreenCaptureAccess() else {
            return CheckOutcome(
                .fail(suspectedCause: "Space Maker hasn't been granted Screen Recording, or Sequoia's periodic re-approval lapsed. Allow Space Maker.app under System Settings → Privacy & Security → Screen & System Audio Recording, then re-run the Doctor. Pins stay disabled until this passes."),
                summary: "Screen Recording isn't granted."
            )
        }

        let box = ResultBox()
        Task.detached { box.set(await captureOneWindow()) }
        let deadline = Date().addingTimeInterval(timeout)
        while box.get() == nil, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let result = box.get() else {
            return CheckOutcome(
                .fail(suspectedCause: "ScreenCaptureKit didn't answer within \(Int(timeout))s. Its daemon may be stuck; try again after logging out and in. Pins stay disabled until this passes."),
                summary: "ScreenCaptureKit timed out."
            )
        }
        switch result {
        case .captured(let detail):
            return CheckOutcome(.pass, summary: "Captured a single window with ScreenCaptureKit.", details: [detail])
        case .noWindow:
            return CheckOutcome(.skipped(reason: "No other app has a window on screen to capture."), summary: "Listed shareable content, but no window to capture. Pins stay enabled.")
        case .failed(let error):
            return CheckOutcome(
                .fail(suspectedCause: "ScreenCaptureKit refused to capture a window: \(error). Screen Recording may need re-approving in System Settings → Privacy & Security. Pins stay disabled until this passes."),
                summary: "ScreenCaptureKit couldn't capture a window."
            )
        }
    }

    enum Result: Sendable {
        case captured(String)
        case noWindow
        case failed(String)
    }

    private static func captureOneWindow() async -> Result {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            let ownPID = ProcessInfo.processInfo.processIdentifier
            guard let window = content.windows.first(where: {
                $0.windowLayer == 0 && $0.frame.width >= 100 && $0.frame.height >= 100
                    && $0.owningApplication.map { $0.processID != ownPID } ?? false
            }) else { return .noWindow }
            let configuration = SCStreamConfiguration()
            configuration.width = 200
            configuration.height = 150
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration
            )
            let app = window.owningApplication?.applicationName ?? "unknown app"
            return .captured("Window \(window.windowID) of \(app): \(image.width)×\(image.height) image.")
        } catch {
            return .failed(String(describing: error))
        }
    }

    private final class ResultBox: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Result?
        func set(_ result: Result) { lock.withLock { value = result } }
        func get() -> Result? { lock.withLock { value } }
    }
}
