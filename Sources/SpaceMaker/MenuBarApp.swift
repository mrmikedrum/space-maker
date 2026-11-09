import AppKit
import ServiceManagement
import SpaceMakerCore

/// The menu bar shell: a thin client of the engine. It owns the command socket the MCP server talks to.
@MainActor
final class MenuBarApp: NSObject, NSApplicationDelegate {
    private let skyLight = SkyLight()
    private lazy var windowSystem = MacWindowSystem(skyLight: skyLight)
    private lazy var engine = Engine(windowSystem: windowSystem) { [unowned self] in self.runDoctorForReport() }
    private var statusItem: NSStatusItem?
    private var server: CommandServer?

    static func makeDoctor(skyLight: SkyLight, windowSystem: MacWindowSystem? = nil) -> Doctor {
        let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let helper = executable.deletingLastPathComponent().appendingPathComponent("space-maker-move-helper")
        return StandardDoctor.make(
            skyLight: skyLight, windowSystem: windowSystem, helperExecutable: helper,
            logsDirectory: StandardDoctor.defaultLogsDirectory
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let engine = engine
        do {
            server = try CommandServer.start(socketPath: CommandSocket.defaultPath) { request in
                await engine.perform(request)
            }
        } catch CommandRelayError.alreadyRunning {
            log("Another Space Maker is already running; quitting.")
            NSApp.terminate(nil)
            return
        } catch {
            log("Couldn't open the command socket, so MCP won't work: \(error)")
        }

        registerLoginItem()
        installStatusItem()
        // Doctor at launch, once the menu bar item is showing.
        DispatchQueue.main.async { _ = self.runDoctor() }
    }

    func applicationWillTerminate(_ notification: Notification) {
        server?.stop()
    }

    // MARK: - Menu

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let image = NSImage(systemSymbolName: "rectangle.3.group", accessibilityDescription: "Space Maker")
        image?.isTemplate = true
        item.button?.image = image

        let menu = NSMenu()
        menu.addItem(menuItem("Run Doctor", #selector(doctorClicked)))
        menu.addItem(menuItem("Open Layout File", #selector(openLayoutClicked)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Space Maker", #selector(quitClicked), key: "q"))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func doctorClicked() {
        if let report = runDoctor() { NSWorkspace.shared.open(report) }
    }

    @objc private func openLayoutClicked() {
        let layout = LayoutFile.defaultURL
        if FileManager.default.fileExists(atPath: layout.path) {
            NSWorkspace.shared.open(layout)
        } else {
            // No Layout until the first Save: show where it will be.
            let folder = layout.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            NSWorkspace.shared.open(folder)
        }
    }

    @objc private func quitClicked() {
        NSApp.terminate(nil)
    }

    // MARK: - Doctor

    /// Runs the Doctor, turns the icon red if any check failed, and returns the report's location.
    private func runDoctor() -> URL? {
        let doctor = Self.makeDoctor(skyLight: skyLight, windowSystem: windowSystem)
        do {
            let results = try doctor.run()
            showDoctorFailed(results.contains(where: \.failed))
            return doctor.reportURL
        } catch {
            log("The Doctor couldn't write its report: \(error)")
            showDoctorFailed(true)
            return nil
        }
    }

    private func runDoctorForReport() -> String {
        guard let report = runDoctor() else { return "The Doctor couldn't write its report to \(StandardDoctor.defaultLogsDirectory.path)." }
        return (try? String(contentsOf: report, encoding: .utf8)) ?? "The Doctor wrote its report to \(report.path) but it couldn't be read back."
    }

    private func showDoctorFailed(_ failed: Bool) {
        statusItem?.button?.contentTintColor = failed ? .systemRed : nil
        statusItem?.button?.toolTip = failed ? "Space Maker: the Doctor found a problem" : "Space Maker"
    }

    // MARK: - Login item

    private func registerLoginItem() {
        let service = SMAppService.mainApp
        guard service.status != .enabled else { return }
        do {
            try service.register()
        } catch {
            log("Couldn't register to launch at login (\(service.status.rawValue)): \(error.localizedDescription)")
        }
    }

    private func log(_ message: String) {
        FileHandle.standardError.write(Data("Space Maker: \(message)\n".utf8))
    }
}
