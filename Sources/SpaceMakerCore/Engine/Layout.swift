import Foundation

/// The saved desired state: every Arrangement and every Assignment (spec, Layout schema).
///
/// Persisted as one readable, versioned JSON file the user may edit by hand.
public struct Layout: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    /// Every Space's name, in the order the user first saw them.
    public var spaces: [String]
    public var displaySetups: [DisplaySetupLayout]
    public var assignments: [Assignment]
    /// Bundle IDs of apps the user always Ignores.
    public var ignoredApps: [String]

    public init(
        version: Int = Layout.currentVersion, spaces: [String] = [],
        displaySetups: [DisplaySetupLayout] = [], assignments: [Assignment] = [],
        ignoredApps: [String] = []
    ) {
        self.version = version
        self.spaces = spaces
        self.displaySetups = displaySetups
        self.assignments = assignments
        self.ignoredApps = ignoredApps
    }

    /// `ignoredApps` may be missing from a Layout written before Ignore existed, or trimmed by hand.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        spaces = try container.decode([String].self, forKey: .spaces)
        displaySetups = try container.decode([DisplaySetupLayout].self, forKey: .displaySetups)
        assignments = try container.decode([Assignment].self, forKey: .assignments)
        ignoredApps = try container.decodeIfPresent([String].self, forKey: .ignoredApps) ?? []
    }
}

/// One Display Setup, keyed by its set of known displays, and its Arrangement.
public struct DisplaySetupLayout: Codable, Equatable, Sendable {
    /// The known displays' IDs, sorted.
    public var displays: [String]
    public var arrangement: [DisplayArrangement]

    public init(displays: [String], arrangement: [DisplayArrangement]) {
        self.displays = displays
        self.arrangement = arrangement
    }
}

/// The Spaces on one display, in order: the Nth name is the Nth regular desktop (ADR 0003).
public struct DisplayArrangement: Codable, Equatable, Sendable {
    public var display: String
    public var spaces: [String]

    public init(display: String, spaces: [String]) {
        self.display = display
        self.spaces = spaces
    }
}

/// Where a specific window belongs.
public struct Assignment: Codable, Equatable, Sendable {
    public var window: WindowIdentity
    public var space: String

    public init(window: WindowIdentity, space: String) {
        self.window = window
        self.space = space
    }
}

/// How a window is recognised across launches (spec, Window identity).
///
/// Chrome windows match on app, profile and the fullscreen flag, with their name breaking ties.
/// Other apps match on app and the fullscreen flag, with their title breaking ties.
public struct WindowIdentity: Codable, Hashable, Sendable {
    public static let chromeBundleID = "com.google.Chrome"

    public var bundleID: String
    /// Chrome only: the window's profile, nil if it couldn't be read when Saved.
    public var chromeProfile: String?
    public var isFullscreen: Bool
    /// Chrome only: the window's name (Chrome's `given name`). Named Assignments outlive their window.
    public var name: String?
    /// Other apps only: the window's title when Saved.
    public var title: String?

    public init(bundleID: String, chromeProfile: String? = nil, isFullscreen: Bool = false, name: String? = nil, title: String? = nil) {
        self.bundleID = bundleID
        self.chromeProfile = chromeProfile
        self.isFullscreen = isFullscreen
        self.name = name
        self.title = title
    }

    public var isChrome: Bool { bundleID == Self.chromeBundleID }

    private enum CodingKeys: String, CodingKey {
        case bundleID, chromeProfile, isFullscreen, name, title
    }

    /// `isFullscreen` may be left out of a hand-written Layout; it defaults to false.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        chromeProfile = try container.decodeIfPresent(String.self, forKey: .chromeProfile)
        isFullscreen = try container.decodeIfPresent(Bool.self, forKey: .isFullscreen) ?? false
        name = try container.decodeIfPresent(String.self, forKey: .name)
        title = try container.decodeIfPresent(String.self, forKey: .title)
    }

    /// Orders Assignments in the Layout file so it reads predictably.
    var sortKey: [String] {
        [bundleID, chromeProfile ?? "", isFullscreen ? "1" : "0", name ?? "", title ?? ""]
    }
}

public enum LayoutFileError: Error, CustomStringConvertible {
    case unreadable(URL, String)
    case unsupportedVersion(URL, Int)

    public var description: String {
        switch self {
        case .unreadable(let url, let reason):
            "The Layout file at \(url.path) couldn't be read (\(reason)). Fix or delete it; Space Maker won't overwrite it until then."
        case .unsupportedVersion(let url, let version):
            "The Layout file at \(url.path) is version \(version), but this Space Maker understands version \(Layout.currentVersion)."
        }
    }
}

/// Where the Layout lives, and how it's read and written.
public enum LayoutFile {
    public static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/space-maker/layout.json")
    }

    /// The file's bytes, or nil if there's no Layout yet.
    static func readData(at url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    static func decode(_ data: Data, from url: URL) throws -> Layout {
        struct Versioned: Decodable { var version: Int }
        let version: Int
        do {
            version = try JSONDecoder().decode(Versioned.self, from: data).version
        } catch {
            throw LayoutFileError.unreadable(url, Self.reason(error))
        }
        guard version == Layout.currentVersion else { throw LayoutFileError.unsupportedVersion(url, version) }
        do {
            return try JSONDecoder().decode(Layout.self, from: data)
        } catch {
            throw LayoutFileError.unreadable(url, Self.reason(error))
        }
    }

    static func encode(_ layout: Layout) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try! encoder.encode(layout)
        data.append(UInt8(ascii: "\n"))
        return data
    }

    /// Writes atomically, so a reader (or the watcher) never sees half a file.
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private static func reason(_ error: Error) -> String {
        switch error {
        case DecodingError.dataCorrupted(let context): context.debugDescription
        case DecodingError.keyNotFound(let key, _): "missing \"\(key.stringValue)\""
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            "\(context.codingPath.map(\.stringValue).joined(separator: ".")): \(context.debugDescription)"
        default: error.localizedDescription
        }
    }
}
