import AppKit
import ServiceManagement
import SpaceMakerCore

/// The menu bar shell: a thin client of the engine. It owns the command socket the MCP server talks to.
@MainActor
final class MenuBarApp: NSObject, NSApplicationDelegate {
    private let skyLight = SkyLight()
    private lazy var windowSystem = MacWindowSystem(skyLight: skyLight)
    private lazy var engine = Engine(windowSystem: windowSystem, layoutURL: LayoutFile.defaultURL) { [unowned self] in self.runDoctorForReport() }
    private var statusItem: NSStatusItem?
    private var server: CommandServer?
    private var layoutWatcher: LayoutWatcher?

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

        layoutWatcher = LayoutWatcher(url: LayoutFile.defaultURL) { [weak self] in self?.engine.layoutFileChanged() }
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
        menu.addItem(menuItem("Save All", #selector(saveAllClicked)))
        menu.addItem(menuItem("Restore All", #selector(restoreAllClicked)))
        menu.addItem(menuItem("Pin or Unpin Frontmost Window", #selector(pinFrontmostClicked)))
        menu.addItem(.separator())
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

    @objc private func saveAllClicked() {
        perform("save", failureTitle: "Space Maker couldn't Save")
    }

    @objc private func restoreAllClicked() {
        perform("restore", failureTitle: "Space Maker couldn't Restore everything")
    }

    /// Runs a command through the engine, as MCP would, and only speaks up when something went wrong.
    private func perform(_ command: String, failureTitle: String) {
        let reply = engine.perform(CommandRequest(command: command))
        guard reply.isError || reply.text.contains("Couldn't") else { return }
        let alert = NSAlert()
        alert.messageText = failureTitle
        alert.informativeText = reply.text
        NSApp.activate()
        alert.runModal()
    }

    @objc private func pinFrontmostClicked() {
        let reply = engine.togglePinOfFrontmostWindow()
        guard reply.isError else { return }
        let alert = NSAlert()
        alert.messageText = "Space Maker couldn't Pin"
        alert.informativeText = reply.text
        NSApp.activate()
        alert.runModal()
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
            engine.setMovesDisabled(because: StandardDoctor.moveFailure(in: results))
            showDoctorFailed(results.contains(where: \.failed))
            updatePins(from: results)
            return doctor.reportURL
        } catch {
            log("The Doctor couldn't write its report: \(error)")
            showDoctorFailed(true)
            return nil
        }
    }

    /// A failed screen capture check disables only Pins.
    private func updatePins(from results: [CheckResult]) {
        guard let capture = results.first(where: { $0.title == StandardDoctor.screenCaptureTitle }) else { return }
        if capture.failed {
            engine.disablePins(because: capture.outcome.summary)
        } else {
            engine.enablePins()
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
