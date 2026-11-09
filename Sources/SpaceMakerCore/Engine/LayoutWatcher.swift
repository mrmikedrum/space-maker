import Foundation

/// Watches the Layout file's folder, so hand edits reach the engine. Atomic saves (ours and most
/// editors') replace the file, so the folder is watched rather than the file itself.
///
/// Not unit tested: tests call `Engine.layoutFileChanged()` directly, and every command re-reads a changed file anyway.
public final class LayoutWatcher {
    private let source: DispatchSourceFileSystemObject?

    public init(url: URL, onChange: @escaping @MainActor () -> Void) {
        let folder = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else {
            source = nil
            return
        }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { onChange() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        self.source = source
    }

    deinit {
        source?.cancel()
    }
}
