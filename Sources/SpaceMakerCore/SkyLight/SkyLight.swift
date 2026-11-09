import Foundation
import ObjectiveC

/// The only place Space Maker touches private SkyLight API (ADR 0001).
///
/// Every entry point is resolved at runtime and may be missing on a given macOS build, so each
/// one is optional and reported individually through `missingSymbols`.
public final class SkyLight: @unchecked Sendable {
    public static let imagePath = "/System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight"

    /// A native macOS desktop as SkyLight reports it.
    public struct NativeDesktop: Equatable, Sendable {
        public enum Kind: Equatable, Sendable {
            case regular
            case fullscreen
            case other(Int)
        }

        public let id: UInt64
        public let kind: Kind
    }

    /// One display's desktops, in Mission Control order.
    public struct DisplayDesktops: Equatable, Sendable {
        public let displayIdentifier: String
        public let currentDesktopID: UInt64?
        public let desktops: [NativeDesktop]

        public var regularDesktopIDs: [UInt64] { desktops.filter { $0.kind == .regular }.map(\.id) }
    }

    public struct Symbol: Sendable {
        public let name: String
        public let isPresent: Bool
    }

    private typealias MainConnectionIDFn = @convention(c) () -> Int32
    private typealias CopyManagedDisplaySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?
    private typealias CopySpacesForWindowsFn = @convention(c) (Int32, Int32, CFArray) -> Unmanaged<CFArray>?
    private typealias PerformBridgedOperationFn = @convention(c) (UnsafeMutableRawPointer) -> Int64
    private typealias InitMoveOperationFn = @convention(c) (UnsafeMutableRawPointer, Selector, CFArray, UInt64) -> UnsafeMutableRawPointer?

    private static let performBridgedOperationSymbol =
        "__ZL54SLSPerformAsynchronousBridgedWindowManagementOperationP47SLSAsynchronousBridgedWindowManagementOperation"
    private static let moveOperationClassName = "SLSBridgedMoveWindowsToManagedSpaceOperation"
    private static let moveOperationInitializer = "initWithWindows:spaceID:"
    /// Asks SkyLight for every desktop a window is on (current, other and fullscreen desktops).
    private static let allDesktopsMask: Int32 = 0x7

    private let mainConnectionID: MainConnectionIDFn?
    private let copyManagedDisplaySpaces: CopyManagedDisplaySpacesFn?
    private let copySpacesForWindows: CopySpacesForWindowsFn?
    private let performBridgedOperation: PerformBridgedOperationFn?
    private let moveOperationClass: AnyClass?
    private let moveOperationInit: InitMoveOperationFn?

    public let symbols: [Symbol]

    public init() {
        let handle = dlopen(Self.imagePath, RTLD_LAZY)

        func exported<T>(_ name: String, as type: T.Type) -> T? {
            guard let handle, let pointer = dlsym(handle, name) else { return nil }
            return unsafeBitCast(pointer, to: type)
        }

        mainConnectionID = exported("SLSMainConnectionID", as: MainConnectionIDFn.self)
        copyManagedDisplaySpaces = exported("SLSCopyManagedDisplaySpaces", as: CopyManagedDisplaySpacesFn.self)
        copySpacesForWindows = exported("SLSCopySpacesForWindows", as: CopySpacesForWindowsFn.self)
        performBridgedOperation = MachOSymbols.find(symbol: Self.performBridgedOperationSymbol, inImage: Self.imagePath)
            .map { unsafeBitCast($0, to: PerformBridgedOperationFn.self) }

        moveOperationClass = NSClassFromString(Self.moveOperationClassName)
        let initSelector = NSSelectorFromString(Self.moveOperationInitializer)
        if let moveOperationClass, class_getInstanceMethod(moveOperationClass, initSelector) != nil {
            moveOperationInit = unsafeBitCast(class_getMethodImplementation(moveOperationClass, initSelector), to: InitMoveOperationFn.self)
        } else {
            moveOperationInit = nil
        }

        symbols = [
            Symbol(name: "SLSMainConnectionID", isPresent: mainConnectionID != nil),
            Symbol(name: "SLSCopyManagedDisplaySpaces", isPresent: copyManagedDisplaySpaces != nil),
            Symbol(name: "SLSCopySpacesForWindows", isPresent: copySpacesForWindows != nil),
            Symbol(name: "SLSPerformAsynchronousBridgedWindowManagementOperation (non-exported)", isPresent: performBridgedOperation != nil),
            Symbol(name: "class \(Self.moveOperationClassName)", isPresent: moveOperationClass != nil),
            Symbol(name: "-[\(Self.moveOperationClassName) \(Self.moveOperationInitializer)]", isPresent: moveOperationInit != nil),
        ]
    }

    public var missingSymbols: [String] { symbols.filter { !$0.isPresent }.map(\.name) }
    public var canReadDesktops: Bool { mainConnectionID != nil && copyManagedDisplaySpaces != nil && copySpacesForWindows != nil }
    public var canMoveWindows: Bool { mainConnectionID != nil && performBridgedOperation != nil && moveOperationInit != nil }

    private var connection: Int32? { mainConnectionID?() }

    /// Every display's desktops, or nil if SkyLight can't be read.
    public func displayDesktops() -> [DisplayDesktops]? {
        guard let copyManagedDisplaySpaces, let connection,
              let displays = copyManagedDisplaySpaces(connection)?.takeRetainedValue() as? [[String: Any]]
        else { return nil }

        return displays.map { display in
            let current = (display["Current Space"] as? [String: Any]).flatMap(Self.desktopID)
            let desktops = (display["Spaces"] as? [[String: Any]] ?? []).compactMap { space -> NativeDesktop? in
                guard let id = Self.desktopID(space) else { return nil }
                let type = (space["type"] as? NSNumber)?.intValue ?? -1
                let kind: NativeDesktop.Kind = switch type {
                case 0: .regular
                case 4: .fullscreen
                default: .other(type)
                }
                return NativeDesktop(id: id, kind: kind)
            }
            return DisplayDesktops(
                displayIdentifier: display["Display Identifier"] as? String ?? "unknown",
                currentDesktopID: current,
                desktops: desktops
            )
        }
    }

    /// The desktops a window is on, or nil if SkyLight can't be read.
    public func desktopIDs(forWindow windowID: UInt32) -> [UInt64]? {
        guard let copySpacesForWindows, let connection else { return nil }
        guard let ids = copySpacesForWindows(connection, Self.allDesktopsMask, Self.windowList(windowID))?.takeRetainedValue() as? [NSNumber]
        else { return nil }
        return ids.map(\.uint64Value)
    }

    /// Asks WindowServer to move another app's window to a desktop. Asynchronous: the move may land
    /// later or be silently ignored, so callers must verify with `desktopIDs(forWindow:)`.
    /// Returns false only if the operation couldn't be issued at all.
    public func moveWindow(_ windowID: UInt32, toDesktop desktopID: UInt64) -> Bool {
        guard let performBridgedOperation, let moveOperationClass, let moveOperationInit else { return false }

        // +1 from alloc is consumed by init, which returns its own +1 that ARC takes over.
        guard let allocated = (moveOperationClass as AnyObject).perform(NSSelectorFromString("alloc"))?.toOpaque(),
              let initialized = moveOperationInit(allocated, NSSelectorFromString(Self.moveOperationInitializer), Self.windowList(windowID), desktopID)
        else { return false }
        let operation = Unmanaged<AnyObject>.fromOpaque(initialized).takeRetainedValue()

        withExtendedLifetime(operation) {
            _ = performBridgedOperation(Unmanaged.passUnretained(operation).toOpaque())
        }
        return true
    }

    private static func windowList(_ windowID: UInt32) -> CFArray {
        [NSNumber(value: Int32(bitPattern: windowID))] as CFArray
    }

    private static func desktopID(_ space: [String: Any]) -> UInt64? {
        (space["id64"] as? NSNumber)?.uint64Value ?? (space["ManagedSpaceID"] as? NSNumber)?.uint64Value
    }
}
