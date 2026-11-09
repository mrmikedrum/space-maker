import Foundation
import SpaceMakerCore
import Testing

@MainActor
struct ChromeIdentityTests {
    let world = FakeWindowSystem()
    let layoutURL = URL.temporaryLayout()

    func engine() -> Engine { Engine(windowSystem: world, layoutURL: layoutURL) }

    /// Three regular desktops (11 current, 12, 13) and a fullscreen desktop (14) on the built-in display.
    func desktops() {
        world.displays = [.builtIn(desktops: [
            .init(id: 11, kind: .regular, isCurrent: true),
            .init(id: 12, kind: .regular, isCurrent: false),
            .init(id: 13, kind: .regular, isCurrent: false),
            .init(id: 14, kind: .fullscreen, isCurrent: false),
        ])]
    }

    @Test func everySavedChromeWindowIsNamedSoItsFoundEvenWhenItsProfileCantBeReadLater() throws {
        desktops()
        world.windows = [
            .chrome(601, profile: .known("Work"), title: "Inbox", desktop: 12),
            .chrome(602, profile: .known("Personal"), title: "News", desktop: 13),
            .chrome(603, profile: .known("Work"), title: "Docs", desktop: 14, fullscreen: true),
        ]
        let engine = engine()
        try engine.run("save")
        #expect(world.windows.allSatisfy { $0.name != nil })

        // After a relaunch the windows are on hidden desktops, where their profile can't be read.
        world.relaunchChrome()
        for index in world.windows.indices { world.windows[index].chromeProfile = .unknown }
        try engine.run("restore")

        #expect(world.desktop(of: 1601) == 12)
        #expect(world.desktop(of: 1602) == 13)
    }

    @Test func saveNamesTwoSameProfileWindowsAndARelaunchStillMatchesEveryWindow() throws {
        desktops()
        world.windows = [
            .chrome(601, profile: .known("Work"), title: "Inbox", desktop: 12),
            .chrome(602, profile: .known("Work"), title: "Calendar", desktop: 13),
            .chrome(603, profile: .known("Personal"), title: "News", desktop: 11),
        ]
        let engine = engine()
        try engine.run("save")

        let first = try #require(world.window(601)?.name)
        let second = try #require(world.window(602)?.name)
        #expect(first != second)
        #expect(world.window(603)?.name != nil)  // every saved Chrome window is named, even the only Personal one

        world.relaunchChrome()
        world.move(1603, to: 13)
        try engine.run("restore")

        #expect(world.desktop(of: 1601) == 12)
        #expect(world.desktop(of: 1602) == 13)
        #expect(world.desktop(of: 1603) == 11)
    }

    @Test func savingOneChromeWindowThatLooksLikeAnotherNamesItToo() throws {
        desktops()
        world.windows = [.chrome(601, profile: .known("Work"), title: "Inbox", desktop: 12)]
        let engine = engine()
        try engine.run("save")
        let first = try #require(world.window(601)?.name)
        world.openWindow(.chrome(602, profile: .known("Work"), title: "Calendar", desktop: 13))
        let handle = try #require(engine.status().windows.first { $0.title == "Calendar" }?.handle)

        let reply = try engine.run("save", ["window": handle])

        let name = try #require(world.window(602)?.name)
        #expect(reply.contains("“\(name)”"))
        #expect(world.window(601)?.name == first)  // every other window and Assignment is left alone
        let layout = try JSONDecoder().decode(Layout.self, from: Data(contentsOf: layoutURL))
        #expect(layout.assignments.map { "\($0.window.name ?? "-") → \($0.space)" }.sorted() == ["\(first) → Google Chrome", "\(name) → Desktop 2"])
    }

    @Test func saveDropsClosedUnnamedWindowsButKeepsClosedNamedOnesUntilTheyReturn() throws {
        desktops()
        world.windows = [
            .chrome(601, profile: .known("Work"), title: "Inbox", desktop: 12, name: "Research"),
            .chrome(602, profile: .known("Personal"), title: "News", desktop: 13),
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
        ]
        let engine = engine()
        try engine.run("save")

        world.windows.removeAll { $0.id == 601 || $0.id == 501 }
        try engine.run("save")

        let kept = try savedLayout().assignments.map(\.window)
        #expect(kept.contains { $0.name == "Research" })
        #expect(!kept.contains { $0.bundleID == "com.apple.Terminal" })  // unnamed and closed: dropped

        world.windows.append(.chrome(701, profile: .known("Work"), title: "Inbox", desktop: 11, name: "Research"))
        try engine.run("restore")
        #expect(world.desktop(of: 701) == 12)
    }

    @Test func whenAutomationForChromeIsDeniedSaveStillSucceedsWithoutNamingAndSaysWhy() throws {
        desktops()
        world.chromeAutomationDenied = true
        world.windows = [
            .chrome(601, profile: .known("Work"), title: "Inbox", desktop: 12),
            .chrome(602, profile: .known("Work"), title: "Calendar", desktop: 13),
        ]

        let reply = try engine().run("save")

        #expect(reply.contains("Automation for Google Chrome isn't allowed."))
        #expect(world.windows.allSatisfy { $0.name == nil })
        #expect(try savedLayout().assignments.count == 2)
    }

    @Test func statusShowsEachChromeWindowsProfileNameAndAssignment() throws {
        desktops()
        world.windows = [
            .chrome(601, profile: .known("Work"), title: "Inbox", desktop: 12, name: "Research"),
            .chrome(602, profile: .known("Personal"), title: "News", desktop: 13),
        ]
        let engine = engine()
        try engine.run("save")
        world.windows.append(.chrome(603, profile: .known("Personal"), title: "Mail", desktop: 12))

        let windows = engine.status().windows

        let research = try #require(windows.first { $0.title == "Research" })
        #expect(research.chromeProfile == "Work")
        #expect(research.name == "Research")
        #expect(research.assignment == "Google Chrome")  // desktop 12, named after its main app
        #expect(windows.first { $0.chromeProfile == "Personal" && $0.name != nil }?.assignment == "Google Chrome 2")
        #expect(windows.first { $0.title == "Mail" }?.assignment == nil)  // an extra of its kind matches nothing
    }

    @Test func nameWindowNamesAChromeWindowAndItsAssignmentThenOutlivesTheWindow() throws {
        desktops()
        world.windows = [
            .chrome(601, profile: .known("Work"), title: "Inbox", desktop: 12),
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
        ]
        let engine = engine()
        try engine.run("save")
        let handles = Dictionary(uniqueKeysWithValues: engine.status().windows.map { ($0.title, $0.handle) })

        let chrome = try #require(engine.status().windows.first { $0.chromeProfile == "Work" }?.handle)  // titled by its automatic name now
        try engine.run("name_window", ["window": chrome, "name": "Work second"])

        #expect(world.window(601)?.name == "Work second")
        #expect(try savedLayout().assignments.contains { $0.window.name == "Work second" && $0.space == "Google Chrome" })
        #expect(engine.perform(CommandRequest(command: "name_window", arguments: ["window": handles["zsh"]!, "name": "Shell"])).isError)

        world.windows.removeAll { $0.id == 601 }
        try engine.run("save")
        #expect(try savedLayout().assignments.contains { $0.window.name == "Work second" })
    }

    @Test func aChromeWindowWhoseProfileIsUnknownIsNamedOnSaveAndMatchedByNameLater() throws {
        desktops()
        world.windows = [
            .chrome(601, profile: .known("Work"), title: "Inbox", desktop: 11),
            .chrome(602, profile: .unknown, title: "News", desktop: 13),  // on a hidden desktop
        ]
        let engine = engine()
        try engine.run("save")
        #expect(world.window(601)?.name != nil)
        #expect(world.window(602)?.name != nil)

        world.relaunchChrome()
        world.windows[1].chromeProfile = .known("Personal")  // now on the current desktop, so readable
        try engine.run("restore")

        #expect(world.desktop(of: 1602) == 13)
    }

    @Test func otherAppsMatchOnAppPlusTitleAndALoneWindowOfItsAppMatchesWhateverItsTitle() throws {
        desktops()
        world.windows = [
            .app(501, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 11),
            .app(502, "com.apple.Terminal", "Terminal", title: "logs", desktop: 12),
            .app(503, "com.tinyspeck.slackmacgap", "Slack", title: "general", desktop: 13),
        ]
        let engine = engine()
        try engine.run("save")

        world.move(501, to: 12)
        world.move(502, to: 11)
        world.windows[2].title = "random"
        world.move(503, to: 11)
        // A changed title with another new window of the same app: neither can be told apart, so neither moves.
        world.windows[1].title = "tail"
        world.windows.append(.app(504, "com.apple.Terminal", "Terminal", title: "htop", desktop: 13))
        try engine.run("restore")

        #expect(world.desktop(of: 501) == 11)
        #expect(world.desktop(of: 502) == 11)
        #expect(world.desktop(of: 503) == 13)
        #expect(world.desktop(of: 504) == 13)
    }

    func savedLayout() throws -> Layout {
        try JSONDecoder().decode(Layout.self, from: Data(contentsOf: layoutURL))
    }
}
