import Foundation

/// Where the Layout lives (spec, Layout schema). Reading and writing it arrive with Save and Restore.
public enum LayoutFile {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/space-maker/layout.json")
    }
}
