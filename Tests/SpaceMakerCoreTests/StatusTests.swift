import SpaceMakerCore
import Testing

@MainActor
struct StatusTests {
    let world = FakeWindowSystem()

    @Test func reportsTheBuiltInDisplaysDesktopsInMissionControlOrder() async throws {
        world.displays = [.builtIn(desktops: [
            .init(id: 11, kind: .regular, isCurrent: false),
            .init(id: 12, kind: .fullscreen, isCurrent: true),
            .init(id: 13, kind: .regular, isCurrent: false),
        ])]

        let status = Engine(windowSystem: world, layoutURL: .temporaryLayout()).status()

        #expect(status.displaySetup == [
            DisplayStatus(id: "built-in", name: "Built-in Retina Display", desktops: [
                DesktopStatus(number: 1, kind: .regular, isCurrent: false),
                DesktopStatus(number: 2, kind: .fullscreen, isCurrent: true),
                DesktopStatus(number: 3, kind: .regular, isCurrent: false),
            ]),
        ])
        #expect(status.guestDisplays.isEmpty)
    }

    @Test func reportsEachWindowWithItsAppTitleFullscreenFlagAndDesktop() async throws {
        world.displays = [.builtIn(desktops: [
            .init(id: 11, kind: .regular, isCurrent: true),
            .init(id: 12, kind: .fullscreen, isCurrent: false),
        ])]
        world.windows = [
            .app(501, "com.ticktick.task.mac", "TickTick", title: "Today", desktop: 11),
            .app(502, "com.apple.Terminal", "Terminal", title: "zsh", desktop: 12, fullscreen: true),
        ]

        let status = Engine(windowSystem: world, layoutURL: .temporaryLayout()).status()

        #expect(status.windows == [
            WindowStatus(handle: "w1", app: "TickTick", bundleID: "com.ticktick.task.mac", chromeProfile: nil,
                         isFullscreen: false, title: "Today", desktop: DesktopReference(display: "built-in", number: 1)),
            WindowStatus(handle: "w2", app: "Terminal", bundleID: "com.apple.Terminal", chromeProfile: nil,
                         isFullscreen: true, title: "zsh", desktop: DesktopReference(display: "built-in", number: 2)),
        ])
    }

    @Test func reportsEveryDisplayOtherThanTheBuiltInOneAsAGuestDisplay() async throws {
        world.displays = [
            .builtIn(desktops: [.init(id: 11, kind: .regular, isCurrent: true)]),
            .external("4K-UUID", name: "LG UltraFine", desktops: [
                .init(id: 21, kind: .regular, isCurrent: true),
                .init(id: 22, kind: .regular, isCurrent: false),
            ]),
        ]
        world.windows = [.app(501, "com.apple.Safari", "Safari", title: "News", desktop: 22)]

        let status = Engine(windowSystem: world, layoutURL: .temporaryLayout()).status()

        #expect(status.displaySetup.map(\.id) == ["built-in"])
        #expect(status.guestDisplays == [
            DisplayStatus(id: "4K-UUID", name: "LG UltraFine", desktops: [
                DesktopStatus(number: 1, kind: .regular, isCurrent: true),
                DesktopStatus(number: 2, kind: .regular, isCurrent: false),
            ]),
        ])
        #expect(status.windows.map(\.desktop) == [DesktopReference(display: "4K-UUID", number: 2)])
    }

    @Test func reportsAChromeWindowsProfileOrUnknownWhenItCantBeRead() async throws {
        world.displays = [.builtIn(desktops: [.init(id: 11, kind: .regular, isCurrent: true)])]
        world.windows = [
            .chrome(601, profile: .known("Work"), title: "Inbox", desktop: 11),
            .chrome(602, profile: .unknown, title: "Docs", desktop: 11),
            .app(603, "com.apple.Safari", "Safari", title: "News", desktop: 11),
        ]

        let status = Engine(windowSystem: world, layoutURL: .temporaryLayout()).status()

        #expect(status.windows.map(\.chromeProfile) == ["Work", "unknown", nil])
    }

    @Test func aWindowKeepsItsHandleWhileItLivesAndHandlesAreNeverReused() async throws {
        world.displays = [.builtIn(desktops: [.init(id: 11, kind: .regular, isCurrent: true)])]
        world.windows = [
            .app(501, "com.apple.Safari", "Safari", title: "News", desktop: 11),
            .app(502, "com.apple.Notes", "Notes", title: "List", desktop: 11),
        ]
        let engine = Engine(windowSystem: world, layoutURL: .temporaryLayout())
        #expect(engine.status().windows.map(\.handle) == ["w1", "w2"])

        world.windows = [
            .app(503, "com.apple.Mail", "Mail", title: "Inbox", desktop: 11),
            .app(502, "com.apple.Notes", "Notes", title: "List (renamed)", desktop: 11),
        ]

        #expect(engine.status().windows.map(\.handle) == ["w3", "w2"])
    }

    @Test func leavesOutPanelsDialogsAndSheets() async throws {
        world.displays = [.builtIn(desktops: [.init(id: 11, kind: .regular, isCurrent: true)])]
        world.windows = [
            .app(501, "com.apple.Safari", "Safari", title: "News", desktop: 11),
            .app(502, "com.apple.Safari", "Safari", title: "Downloads", desktop: 11, isStandard: false),
        ]

        let status = Engine(windowSystem: world, layoutURL: .temporaryLayout()).status()

        #expect(status.windows.map(\.title) == ["News"])
    }
}
