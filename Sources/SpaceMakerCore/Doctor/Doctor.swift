import Foundation

/// What one Doctor check found. Checks are independent: a failure in one never stops the others.
public struct CheckOutcome: Sendable {
    public enum Status: Sendable {
        case pass
        case fail(suspectedCause: String)
        case skipped(reason: String)
    }

    public let status: Status
    public let summary: String
    public let details: [String]

    public init(_ status: Status, summary: String, details: [String] = []) {
        self.status = status
        self.summary = summary
        self.details = details
    }
}

/// A check's outcome under the check's title.
public struct CheckResult: Sendable {
    public let title: String
    public let outcome: CheckOutcome
    public var status: CheckOutcome.Status { outcome.status }

    public var passed: Bool {
        if case .pass = status { return true }
        return false
    }

    public var failed: Bool {
        if case .fail = status { return true }
        return false
    }
}

public struct DoctorCheck: Sendable {
    public let title: String
    public let run: @MainActor @Sendable () async -> CheckOutcome

    public init(title: String, run: @escaping @MainActor @Sendable () async -> CheckOutcome) {
        self.title = title
        self.run = run
    }
}

/// Runs checks in order and keeps the report on disk up to date after every step, so a check that
/// crashes the process still leaves a report naming the check that was running.
@MainActor
public final class Doctor {
    public let reportURL: URL
    private let environment: [(String, String)]
    private let verdict: ([CheckResult]) -> String
    private let checks: [DoctorCheck]

    public init(
        logsDirectory: URL,
        environment: [(String, String)],
        checks: [DoctorCheck],
        verdict: @escaping ([CheckResult]) -> String
    ) {
        let stamp = Self.fileTimestamp.string(from: Date())
        self.reportURL = logsDirectory.appendingPathComponent("doctor-\(stamp).md")
        self.environment = environment
        self.checks = checks
        self.verdict = verdict
    }

    /// Returns the results; the report has been written to `reportURL` and linked from `doctor-latest.md`.
    public func run() async throws -> [CheckResult] {
        try FileManager.default.createDirectory(at: reportURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try linkLatest()

        var results: [CheckResult] = []
        for check in checks {
            try write(results: results, running: check.title)
            results.append(CheckResult(title: check.title, outcome: await check.run()))
        }
        try write(results: results, running: nil)
        return results
    }

    private func write(results: [CheckResult], running: String?) throws {
        let markdown = DoctorReport.render(
            generatedAt: Date(),
            verdict: running == nil ? verdict(results) : "INCOMPLETE: the Doctor stopped while running \"\(running!)\".",
            environment: environment,
            results: results,
            running: running
        )
        try markdown.write(to: reportURL, atomically: true, encoding: .utf8)
    }

    private func linkLatest() throws {
        let latest = reportURL.deletingLastPathComponent().appendingPathComponent("doctor-latest.md")
        try? FileManager.default.removeItem(at: latest)
        try FileManager.default.createSymbolicLink(at: latest, withDestinationURL: reportURL)
    }

    private static let fileTimestamp: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        return formatter
    }()
}

enum DoctorReport {
    static func render(
        generatedAt: Date,
        verdict: String,
        environment: [(String, String)],
        results: [CheckResult],
        running: String?
    ) -> String {
        var lines = [
            "# Space Maker Doctor report",
            "",
            "Generated \(ISO8601DateFormatter().string(from: generatedAt))",
            "",
            "**Verdict:** \(verdict)",
            "",
            "## Environment",
            "",
            "| | |",
            "| --- | --- |",
        ]
        lines += environment.map { "| \($0.0) | \($0.1) |" }

        lines += ["", "## Checks", "", "| Check | Result |", "| --- | --- |"]
        for result in results {
            lines.append("| \(result.title) | \(label(result.status)): \(result.outcome.summary) |")
        }
        if let running {
            lines.append("| \(running) | ⏳ Running (if this is still here, the check crashed or hung the Doctor) |")
        }

        for result in results {
            lines += ["", "### \(result.title): \(label(result.status))", "", result.outcome.summary]
            if !result.outcome.details.isEmpty {
                lines.append("")
                lines += result.outcome.details.map { "- \($0)" }
            }
            switch result.status {
            case .fail(let cause): lines += ["", "**Suspected cause:** \(cause)"]
            case .skipped(let reason): lines += ["", "**Skipped because:** \(reason)"]
            case .pass: break
            }
        }

        lines += [
            "",
            "## For an agent fixing this",
            "",
            "- All private API access lives in the `SkyLight` component of `SpaceMakerCore` (ADR 0001). Checks live in `SpaceMakerCore/Doctor`.",
            "- Reference implementation for the SIP-on move: yabai `src/space_manager.c` (`space_manager_move_window_to_space`) and `src/misc/macho_dlsym.h`, https://github.com/asmvik/yabai.",
            "- Background and platform facts: `.scratch/space-maker-v1/spec.md`, Further Notes.",
            "- Re-run with `scripts/doctor.sh` so macOS attributes permissions to Space Maker itself rather than to the terminal.",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    private static func label(_ status: CheckOutcome.Status) -> String {
        switch status {
        case .pass: "✅ Pass"
        case .fail: "❌ Fail"
        case .skipped: "⏭ Skipped"
        }
    }
}
