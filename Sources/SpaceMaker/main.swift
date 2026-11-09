import AppKit
import SpaceMakerCore

let usage = """
usage: SpaceMaker --doctor

  --doctor   Run the Doctor, write a report to ~/Library/Logs/SpaceMaker/, print its path,
             and exit 0 if every check passed (1 otherwise).

Run it through scripts/doctor.sh so macOS attributes permissions to Space Maker itself.
"""

let arguments = CommandLine.arguments.dropFirst()
guard arguments.contains("--doctor") else {
    print(usage)
    exit(arguments.isEmpty ? 0 : 64)
}

MainActor.assumeIsolated {
    _ = NSApplication.shared  // SkyLight expects an AppKit connection to WindowServer.
    let executable = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
    let helper = executable.deletingLastPathComponent().appendingPathComponent("space-maker-move-helper")
    let doctor = StandardDoctor.make(skyLight: SkyLight(), helperExecutable: helper, logsDirectory: StandardDoctor.defaultLogsDirectory)
    do {
        let results = try doctor.run()
        print(doctor.reportURL.path)
        exit(results.allSatisfy(\.passed) ? 0 : 1)
    } catch {
        FileHandle.standardError.write(Data("Doctor could not write its report: \(error.localizedDescription)\n".utf8))
        exit(2)
    }
}
