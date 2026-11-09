import AppKit
import ApplicationServices
import Foundation

/// Notices windows appearing, for Placement: an Accessibility observer per regular app for new windows,
/// plus a sweep of a newly launched app's windows, since an app restoring its session (Chrome) can open
/// windows before its observer exists.
///
/// The same window may be announced more than once; the engine gives each window one chance.
/// Not unit tested; pending the live demo.
@MainActor
final class WindowAppearanceObserver {
    /// How long to wait after a window is created before announcing it, so macOS lists it on a desktop.
    private static let settleDelay: TimeInterval = 0.5
    /// When to sweep a newly launched app's windows, after launch.
    private static let launchSweeps: [TimeInterval] = [1, 3, 6]

    private let onAppeared: @MainActor (UInt32) -> Void
    private var observers: [pid_t: AXObserver] = [:]
    private var tokens: [NSObjectProtocol] = []

    init(onAppeared: @escaping @MainActor (UInt32) -> Void) {
        self.onAppeared = onAppeared
        let center = NSWorkspace.shared.notificationCenter
        tokens.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                self?.observeRunningApps()
                if let pid { self?.sweepAfterLaunch(pid) }
            }
        })
        tokens.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let pid = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                if let pid { self?.stopObserving(pid) }
            }
        })
        // Accessibility may be granted after launch; activating an app is a cheap moment to catch up.
        tokens.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.observeRunningApps() }
        })
        observeRunningApps()
    }

    /// Adds an observer for every regular app that doesn't have one yet.
    private func observeRunningApps() {
        guard AXIsProcessTrusted() else { return }
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            let pid = app.processIdentifier
            guard observers[pid] == nil, pid != ProcessInfo.processInfo.processIdentifier else { continue }
            var observer: AXObserver?
            guard AXObserverCreate(pid, Self.callback, &observer) == .success, let observer else { continue }
            let refcon = Unmanaged.passUnretained(self).toOpaque()
            guard AXObserverAddNotification(observer, AXUIElementCreateApplication(pid), kAXWindowCreatedNotification as CFString, refcon) == .success
            else { continue }  // the app isn't ready for Accessibility yet; the next launch or activation retries
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
            observers[pid] = observer
        }
    }

    private func stopObserving(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private static let callback: AXObserverCallback = { _, element, _, refcon in
        guard let refcon else { return }
        let windowID = PrivateAccessibility.windowID(of: element)
        let address = UInt(bitPattern: refcon)  // Sendable; the observer runs on the main run loop
        MainActor.assumeIsolated {
            guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
            let observer = Unmanaged<WindowAppearanceObserver>.fromOpaque(pointer).takeUnretainedValue()
            if let windowID { observer.announce(windowID, after: settleDelay) }
        }
    }

    private func announce(_ windowID: UInt32, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            MainActor.assumeIsolated { self?.onAppeared(windowID) }
        }
    }

    /// Announces every window a newly launched app has open, a few times while it restores its session.
    private func sweepAfterLaunch(_ pid: pid_t) {
        for delay in Self.launchSweeps {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    for windowID in Self.windowIDs(of: pid) { self.onAppeared(windowID) }
                }
            }
        }
    }

    private static func windowIDs(of pid: pid_t) -> [UInt32] {
        let infos = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return infos.compactMap { info in
            guard (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (info[kCGWindowLayer as String] as? Int) == 0
            else { return nil }
            return (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value
        }
    }
}
