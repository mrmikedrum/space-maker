import Foundation
import os

/// Space Maker's unified logging. Watch it live with:
///
///     log stream --level debug --predicate 'subsystem == "com.mdrum.space-maker"'
///
/// or read the last hour with `log show --last 1h --info --debug --predicate 'subsystem == "com.mdrum.space-maker"'`.
/// Anything that holds the main thread longer than `slowThreshold` is logged as a warning (`SLOW`), since the
/// menu bar can't open while the main thread is busy.
public enum Log {
    public static let subsystem = "com.mdrum.space-maker"
    public static let engine = Logger(subsystem: subsystem, category: "engine")
    public static let adapter = Logger(subsystem: subsystem, category: "adapter")
    public static let relay = Logger(subsystem: subsystem, category: "relay")
    public static let menu = Logger(subsystem: subsystem, category: "menu")
    public static let pins = Logger(subsystem: subsystem, category: "pins")

    public static let slowThreshold: TimeInterval = 0.2

    /// Runs `body`, logging how long it took: at debug level normally, as a warning when it's slow.
    @discardableResult
    public static func timed<T>(_ logger: Logger, _ what: @autoclosure () -> String, _ body: () throws -> T) rethrows -> T {
        let start = DispatchTime.now()
        defer {
            let seconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
            let label = what()
            let milliseconds = Int(seconds * 1000)
            if seconds >= slowThreshold {
                logger.warning("SLOW \(label, privacy: .public): \(milliseconds) ms")
            } else {
                logger.debug("\(label, privacy: .public): \(milliseconds) ms")
            }
        }
        return try body()
    }
}
