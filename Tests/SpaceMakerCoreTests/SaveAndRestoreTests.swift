import Foundation
import SpaceMakerCore
import Testing

@MainActor
struct SaveAndRestoreTests {
    let world = FakeWindowSystem()
    let layoutURL = URL.temporaryLayout()

    func engine() -> Engine { Engine(windowSystem: world, layoutURL: layoutURL) }

    /// Three regular desktops on the built-in display: 11, 12, 13.
    func threeDesktops() {
        world.displays = [.builtIn(desktops: [
            .init(id: 11, kind: .regular, isCurrent: true),
            .init(id: 12, kind: .regular, isCurrent: false),
            .init(id: 13, kind: .regular, isCurrent: false),
        ])]
    }

    @Test func restoreAllPutsEveryAssignedWindowBackOnItsSpace() throws {
        threeDesktops()
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
            .app(502, "com.tinyspeck.slackmacgap", "Slack", title: "general", desktop: 12),
            .app(503, "com.apple.Music", "Music", title: "Music", desktop: 13),
        ]
        let engine = engine()
        try engine.run("save")

        world.move(501, to: 13)
        world.move(502, to: 11)
        try engine.run("restore")

        #expect(world.desktop(of: 501) == 11)
        #expect(world.desktop(of: 502) == 12)
        #expect(world.desktop(of: 503) == 13)
    }

    @Test func restoreOnePutsBackOnlyThatWindow() throws {
        threeDesktops()
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
            .app(502, "com.tinyspeck.slackmacgap", "Slack", title: "general", desktop: 12),
        ]
        let engine = engine()
        try engine.run("save")
        let terminal = try handle(of: 501, engine)

        world.move(501, to: 13)
        world.move(502, to: 13)
        try engine.run("restore", ["window": terminal])

        #expect(world.desktop(of: 501) == 11)
        #expect(world.desktop(of: 502) == 13)
    }

    @Test func windowsWithoutAnAssignmentAreNeverMoved() throws {
        threeDesktops()
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]
        let engine = engine()
        try engine.run("save")

        world.windows.append(.app(502, "com.apple.Safari", "Safari", title: "News", desktop: 12))
        world.move(501, to: 13)
        try engine.run("restore")

        #expect(world.desktop(of: 501) == 11)
        #expect(world.desktop(of: 502) == 12)
        let safari = try handle(of: 502, engine)
        #expect(engine.perform(CommandRequest(command: "restore", arguments: ["window": safari])).isError)
        #expect(world.desktop(of: 502) == 12)
    }

    @Test func saveNamesEachNewDesktopAfterItsMainApp() throws {
        threeDesktops()
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
            .app(502, "com.apple.Safari", "Safari", title: "News", desktop: 11),
            .app(503, "com.apple.Terminal", "Terminal", title: "logs", desktop: 11),
            .app(504, "com.tinyspeck.slackmacgap", "Slack", title: "general", desktop: 12),
        ]
        let engine = engine()
        try engine.run("save")

        #expect(try savedLayout().displaySetups == [
            DisplaySetupLayout(displays: ["built-in"], arrangement: [
                DisplayArrangement(display: "built-in", spaces: ["Terminal", "Slack", "Desktop"]),
            ]),
        ])
        #expect(engine.status().displaySetup[0].desktops.map(\.space) == ["Terminal", "Slack", "Desktop"])
    }

    @Test func aDesktopAddedLaterBecomesANewSpaceAndExistingSpacesKeepTheirNames() throws {
        threeDesktops()
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]
        let engine = engine()
        try engine.run("save")
        try engine.run("rename_space", ["space": "Terminal", "name": "Code"])

        world.displays[0].desktops.append(.init(id: 14, kind: .regular, isCurrent: false))
        world.windows.append(.app(502, "com.apple.Terminal", "Terminal", title: "htop", desktop: 14))
        try engine.run("save")

        #expect(try savedLayout().spaces == ["Code", "Desktop", "Desktop 2", "Terminal"])
    }

    @Test func renamingASpaceKeepsItsWindowsAssignedToIt() throws {
        threeDesktops()
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]
        let engine = engine()
        try engine.run("save")

        try engine.run("rename_space", ["space": "Terminal", "name": "Code"])
        world.move(501, to: 12)
        try engine.run("restore")

        #expect(world.desktop(of: 501) == 11)
        #expect(engine.status().displaySetup[0].desktops[0].space == "Code")
        #expect(try savedLayout().assignments == [
            Assignment(window: WindowIdentity(bundleID: "com.apple.Terminal", title: "zsh"), space: "Code"),
        ])
        #expect(engine.perform(CommandRequest(command: "rename_space", arguments: ["space": "Code", "name": "Desktop"])).isError)
    }

    @Test func savingAfterADesktopIsDeletedRemovesItsSpaceFromTheArrangement() throws {
        threeDesktops()
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
            .app(502, "com.tinyspeck.slackmacgap", "Slack", title: "general", desktop: 12),
            .app(503, "com.apple.Music", "Music", title: "Music", desktop: 13),
        ]
        let engine = engine()
        try engine.run("save")

        // Mission Control: the user deletes the Slack desktop, and macOS moves its window to the first.
        world.displays[0].desktops.remove(at: 1)
        world.move(502, to: 11)
        try engine.run("save")

        let layout = try savedLayout()
        #expect(layout.spaces == ["Terminal", "Music"])
        #expect(layout.displaySetups[0].arrangement[0].spaces == ["Terminal", "Music"])
        #expect(layout.assignments.map(\.space) == ["Music", "Terminal", "Terminal"])  // ordered by bundle ID: Music, Terminal, Slack
    }

    @Test func aHandEditToTheLayoutFileIsReloaded() throws {
        threeDesktops()
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]
        let engine = engine()
        try engine.run("save")

        // The user edits the file: Terminal's zsh window now belongs on the third Space.
        let edited = try String(contentsOf: layoutURL, encoding: .utf8)
            .replacingOccurrences(of: "\"space\" : \"Terminal\"", with: "\"space\" : \"Desktop 2\"")
        try edited.write(to: layoutURL, atomically: true, encoding: .utf8)
        engine.layoutFileChanged()
        try engine.run("restore")

        #expect(world.desktop(of: 501) == 13)
    }

    @Test func aBrokenHandEditIsReportedAndNeverOverwritten() throws {
        threeDesktops()
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]
        let engine = engine()
        try engine.run("save")

        try "{ not json".write(to: layoutURL, atomically: true, encoding: .utf8)
        let reply = engine.perform(CommandRequest(command: "save"))

        #expect(reply.isError)
        #expect(reply.text.contains(layoutURL.path))
        #expect(try String(contentsOf: layoutURL, encoding: .utf8) == "{ not json")
    }

    @Test func aLayoutFileThatCantBeReadIsReportedAndNeverOverwritten() throws {
        threeDesktops()
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]
        try engine().run("save")
        let saved = try Data(contentsOf: layoutURL)

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: layoutURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: layoutURL.path) }
        let engine = engine()  // a fresh launch that can't read the file
        let reply = engine.perform(CommandRequest(command: "save"))

        #expect(reply.isError)
        #expect(reply.text.contains(layoutURL.path))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: layoutURL.path)
        #expect(try Data(contentsOf: layoutURL) == saved)
    }

    @Test func theLayoutIsVersionedReadableJSON() throws {
        threeDesktops()
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]
        try engine().run("save")

        let text = try String(contentsOf: layoutURL, encoding: .utf8)
        #expect(text.contains("\"version\" : 1"))
        #expect(text.contains("\n  "))  // pretty-printed for hand editing
    }

    @Test func moveWindowMovesToASpaceAndOptionallySavesTheAssignment() throws {
        threeDesktops()
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
            .app(502, "com.tinyspeck.slackmacgap", "Slack", title: "general", desktop: 12),
        ]
        let engine = engine()
        try engine.run("save")
        let terminal = try handle(of: 501, engine)
        let slack = try handle(of: 502, engine)

        try engine.run("move_window", ["window": terminal, "space": "Desktop"])
        try engine.run("move_window", ["window": slack, "space": "Desktop", "save": "true"])
        #expect(world.desktop(of: 501) == 13)
        #expect(world.desktop(of: 502) == 13)

        try engine.run("restore")
        #expect(world.desktop(of: 501) == 11)
        #expect(world.desktop(of: 502) == 13)
        #expect(engine.perform(CommandRequest(command: "move_window", arguments: ["window": terminal, "space": "Nowhere"])).isError)
    }

    @Test func whenTheDoctorsMoveCheckFailsRestoreAndMoveWindowExplainWhyAndSaveStillWorks() throws {
        threeDesktops()
        world.windows = [.app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11)]
        let engine = engine()
        engine.setMovesDisabled(because: "the window did not land")
        try engine.run("save")
        let terminal = try handle(of: 501, engine)
        world.move(501, to: 12)

        let restore = engine.perform(CommandRequest(command: "restore"))
        let move = engine.perform(CommandRequest(command: "move_window", arguments: ["window": terminal, "space": "Terminal"]))

        #expect(restore.isError && restore.text.contains("the window did not land"))
        #expect(move.isError && move.text.contains("the window did not land"))
        #expect(world.desktop(of: 501) == 12)
        #expect(try engine.run("rename_space", ["space": "Terminal", "name": "Code"]).contains("Code"))
    }

    @Test func aWindowMacOSWontMoveIsReportedAndTheRestAreStillRestored() throws {
        threeDesktops()
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
            .app(502, "com.tinyspeck.slackmacgap", "Slack", title: "general", desktop: 12),
        ]
        let engine = engine()
        try engine.run("save")
        world.move(501, to: 13)
        world.move(502, to: 13)
        world.unmovableWindows = [501]

        let reply = try engine.run("restore")

        #expect(reply.contains("Couldn't restore"))
        #expect(world.desktop(of: 501) == 13)
        #expect(world.desktop(of: 502) == 12)
    }

    func handle(of windowID: UInt32, _ engine: Engine) throws -> String {
        let titles = world.windows.first { $0.id == windowID }.map(\.title)
        return try #require(engine.status().windows.first { $0.title == titles }?.handle)
    }

    func savedLayout() throws -> Layout {
        try JSONDecoder().decode(Layout.self, from: Data(contentsOf: layoutURL))
    }
}

extension Engine {
    /// Runs a command and fails the test if it reports an error.
    @discardableResult
    func run(_ command: String, _ arguments: [String: String] = [:]) throws -> String {
        let reply = perform(CommandRequest(command: command, arguments: arguments))
        if reply.isError { throw CommandFailed(text: reply.text) }
        return reply.text
    }
}

struct CommandFailed: Error, CustomStringConvertible {
    let text: String
    var description: String { text }
}
