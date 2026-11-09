import ApplicationServices
import Foundation

/// The one private Accessibility call Space Maker uses (ADR 0001): mapping an Accessibility window
/// to its WindowServer window ID. Resolved at runtime so a missing symbol degrades instead of crashing.
enum PrivateAccessibility {
    static let windowIDSymbol = "_AXUIElementGetWindow"

    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<UInt32>) -> AXError

    private static let getWindow: GetWindowFn? = {
        guard let handle = dlopen(nil, RTLD_LAZY), let pointer = dlsym(handle, windowIDSymbol) else { return nil }
        return unsafeBitCast(pointer, to: GetWindowFn.self)
    }()

    static var canMapWindows: Bool { getWindow != nil }

    static func windowID(of element: AXUIElement) -> UInt32? {
        guard let getWindow else { return nil }
        var id: UInt32 = 0
        return getWindow(element, &id) == .success ? id : nil
    }

    static let remoteTokenSymbol = "_AXUIElementCreateWithRemoteToken"

    private typealias CreateWithRemoteTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private static let createWithRemoteToken: CreateWithRemoteTokenFn? = {
        guard let handle = dlopen(nil, RTLD_LAZY), let pointer = dlsym(handle, remoteTokenSymbol) else { return nil }
        return unsafeBitCast(pointer, to: CreateWithRemoteTokenFn.self)
    }()

    static var canReachHiddenWindows: Bool { createWithRemoteToken != nil && getWindow != nil }

    /// An app's windows on every desktop, by window ID. An app's `AXWindows` only lists windows on the desktop
    /// being shown, so this builds Accessibility elements directly from remote tokens (the app's PID, a fixed
    /// "coco" marker and an element number), trying element numbers until every window is found or the range
    /// runs out. This is how AltTab reaches windows on other desktops.
    static func windowsOnEveryDesktop(pid: pid_t, wanted: Set<UInt32>) -> [UInt32: AXUIElement] {
        guard let createWithRemoteToken, !wanted.isEmpty else { return [:] }
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })
        var found: [UInt32: AXUIElement] = [:]
        for elementNumber in UInt64(0)..<UInt64(2000) where found.count < wanted.count {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementNumber) { Data($0) })
            guard let element = createWithRemoteToken(token as CFData)?.takeRetainedValue(),
                  let id = windowID(of: element), wanted.contains(id)
            else { continue }
            found[id] = element
        }
        return found
    }
}
