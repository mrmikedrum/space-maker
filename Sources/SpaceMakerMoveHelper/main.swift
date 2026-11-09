import AppKit

// The Doctor's live move test needs a window owned by a different process ("another app").
// This helper opens one plain window, prints its window ID, and exits when stdin closes.

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let window = NSWindow(
    contentRect: NSRect(x: 0, y: 0, width: 340, height: 90),
    styleMask: [.titled],
    backing: .buffered,
    defer: false
)
window.title = "Space Maker: move test"
window.isReleasedWhenClosed = false
let label = NSTextField(labelWithString: "Space Maker is testing window moves. This closes itself.")
label.frame = NSRect(x: 16, y: 34, width: 310, height: 20)
window.contentView?.addSubview(label)
window.center()
window.orderFrontRegardless()

print(window.windowNumber)
fflush(stdout)

FileHandle.standardInput.readabilityHandler = { handle in
    if handle.availableData.isEmpty { exit(0) }
}
// Never outlive a Doctor that died without closing our stdin.
DispatchQueue.main.asyncAfter(deadline: .now() + 60) { exit(0) }

app.run()
