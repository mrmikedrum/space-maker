import AppKit
import CoreMedia
@preconcurrency import ScreenCaptureKit

/// A Pin's live mirror: a ScreenCaptureKit capture of one window, drawn in a floating, non-activating
/// panel that joins every regular Space. Without `.fullScreenAuxiliary` it stays off fullscreen-app
/// desktops. The user can drag and resize it; a click (not a drag) calls `onClick`.
///
/// Not unit tested; verified live (spec, Testing Decisions).
@MainActor
final class PinMirror {
    let windowID: UInt32
    private let panel: MirrorPanel
    private let output: MirrorOutput
    private var stream: SCStream?
    private var isShown = false
    /// Bumped by every start and stop of capture, so a start that finishes after a later hide or show is dropped.
    private var captureGeneration = 0

    /// The source window's stream stopped with an error, which is how a closed window shows up.
    var onCaptureStopped: (() -> Void)?

    /// `sourceFrame` is the pinned window's frame in WindowServer coordinates (top-left origin). The mirror starts
    /// exactly where the window is and the same size, like Picture in Picture; after that it stays wherever the
    /// user drags or resizes it, since hiding and showing it keeps its frame.
    init(windowID: UInt32, sourceFrame: CGRect, onClick: @escaping @MainActor () -> Void) {
        self.windowID = windowID
        let sourceSize = sourceFrame.size
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var frame = NSRect(
            x: sourceFrame.minX, y: primaryHeight - sourceFrame.maxY,
            width: max(160, sourceFrame.width), height: max(90, sourceFrame.height)
        )
        if sourceFrame.isEmpty {
            let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            frame = NSRect(x: visible.maxX - 500, y: visible.maxY - 380, width: 480, height: 360)
        }

        panel = MirrorPanel(contentRect: frame)
        if sourceSize.width > 0, sourceSize.height > 0 { panel.contentAspectRatio = sourceSize }
        let view = MirrorView(frame: NSRect(origin: .zero, size: frame.size))
        view.onClick = onClick
        panel.contentView = view
        output = MirrorOutput(layer: view.layer!)
        output.onStop = { [weak self] in self?.onCaptureStopped?() }
    }

    func show() {
        guard !isShown else { return }
        isShown = true
        panel.orderFrontRegardless()
        startCapture()
    }

    /// Hides the panel and pauses capture; the panel keeps its place and size for next time.
    func hide() {
        guard isShown else { return }
        isShown = false
        panel.orderOut(nil)
        stopCapture()
    }

    func stop() {
        hide()
        panel.close()
    }

    private func startCapture() {
        let windowID = windowID
        let output = output
        let pixelSize = panel.frame.size
        let scale = panel.backingScaleFactor
        captureGeneration += 1
        let generation = captureGeneration
        Task { [weak self] in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard let window = content.windows.first(where: { $0.windowID == windowID }) else {
                    self?.onCaptureStopped?()
                    return
                }
                let configuration = SCStreamConfiguration()
                // Capture at the source's own resolution, capped, so resizing the mirror stays sharp.
                let sourceScale = max(1, min(2, scale))
                configuration.width = Int(max(window.frame.width, pixelSize.width) * sourceScale)
                configuration.height = Int(max(window.frame.height, pixelSize.height) * sourceScale)
                configuration.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                configuration.showsCursor = false
                configuration.queueDepth = 3
                let stream = SCStream(filter: SCContentFilter(desktopIndependentWindow: window), configuration: configuration, delegate: output)
                try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)
                try await stream.startCapture()
                // Rapid hide and show can start several captures; only the latest one, still wanted, is kept.
                guard let self, self.isShown, self.captureGeneration == generation else {
                    try? await stream.stopCapture()
                    return
                }
                if let superseded = self.stream { Task { try? await superseded.stopCapture() } }
                self.stream = stream
            } catch {
                FileHandle.standardError.write(Data("Space Maker: couldn't start the Pin mirror for window \(windowID): \(error)\n".utf8))
            }
        }
    }

    private func stopCapture() {
        captureGeneration += 1  // a capture still starting is stopped as soon as it has
        guard let stream else { return }
        self.stream = nil
        Task { try? await stream.stopCapture() }
    }
}

private final class MirrorPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.titled, .resizable, .nonactivatingPanel, .fullSizeContentView, .utilityWindow],
            backing: .buffered, defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .ignoresCycle]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = true
        backgroundColor = .black
        hasShadow = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the captured frames, moves the panel on drag and reports a click that didn't drag.
private final class MirrorView: NSView {
    var onClick: (@MainActor () -> Void)?
    private var dragStart: NSPoint?
    private var dragged = false

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.contentsGravity = .resizeAspect
        layer?.backgroundColor = NSColor.black.cgColor
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        dragStart = NSEvent.mouseLocation
        dragged = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, let dragStart else { return }
        let now = NSEvent.mouseLocation
        let delta = NSPoint(x: now.x - dragStart.x, y: now.y - dragStart.y)
        if !dragged, hypot(delta.x, delta.y) < 3 { return }
        dragged = true
        window.setFrameOrigin(NSPoint(x: window.frame.origin.x + delta.x, y: window.frame.origin.y + delta.y))
        self.dragStart = now
    }

    override func mouseUp(with event: NSEvent) {
        defer { dragStart = nil }
        if !dragged { onClick?() }
    }
}

/// Receives frames on a background queue and puts each on the mirror's layer.
private final class MirrorOutput: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    let queue = DispatchQueue(label: "Space Maker Pin mirror")
    /// Only touched on the main queue.
    private let layer: CALayer
    @MainActor var onStop: (() -> Void)?

    init(layer: CALayer) {
        self.layer = layer
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen, let pixelBuffer = sampleBuffer.imageBuffer,
              let surface = CVPixelBufferGetIOSurface(pixelBuffer)?.takeUnretainedValue()
        else { return }
        let frame = UncheckedFrame(surface: surface)
        DispatchQueue.main.async {
            self.layer.contents = frame.surface
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.onStop?() }
        }
    }
}

/// An IOSurface handed from the capture queue to the main queue, which then owns it.
private struct UncheckedFrame: @unchecked Sendable {
    let surface: IOSurface
}
