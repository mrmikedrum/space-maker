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
}
