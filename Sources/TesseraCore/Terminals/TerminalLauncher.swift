import Foundation

public struct TerminalLauncher: Sendable {
    public init() {}

    public func execute(_ plan: LaunchPlan) async -> LaunchResult {
        await Task.detached(priority: .userInitiated) {
            self.executeSync(plan)
        }.value
    }

    public func executeSync(_ plan: LaunchPlan) -> LaunchResult {
        switch plan.action {
        case .appleScript(let script):
            return runProcess(
                executablePath: "/usr/bin/osascript",
                arguments: ["-"],
                stdin: script,
                terminal: plan.terminal,
                layoutName: plan.layoutName
            )

        case .shellScript(let script):
            return runProcess(
                executablePath: "/bin/zsh",
                arguments: ["-s"],
                stdin: script,
                terminal: plan.terminal,
                layoutName: plan.layoutName
            )

        case .writeFileAndRunShell(let filePath, let fileContent, let shellCommand):
            do {
                let url = URL(fileURLWithPath: filePath)
                let parent = url.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
                try fileContent.write(to: url, atomically: true, encoding: .utf8)
                // Protect generated terminal session configs (may contain env vars) to owner-only read/write
                try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            } catch {
                return LaunchResult(
                    terminal: plan.terminal,
                    layoutName: plan.layoutName,
                    succeeded: false,
                    message: "Failed to write terminal configuration to \(filePath): \(error.localizedDescription)"
                )
            }

            return runProcess(
                executablePath: "/bin/zsh",
                arguments: ["-lc", shellCommand],
                stdin: nil,
                terminal: plan.terminal,
                layoutName: plan.layoutName
            )
        }
    }

    private func runProcess(
        executablePath: String,
        arguments: [String],
        stdin: String?,
        terminal: TerminalKind,
        layoutName: String
    ) -> LaunchResult {
        do {
            let result = try SubprocessRunner.run(
                executablePath: executablePath,
                arguments: arguments,
                stdin: stdin,
                timeoutSeconds: 20.0
            )

            if result.timedOut {
                return LaunchResult(
                    terminal: terminal,
                    layoutName: layoutName,
                    succeeded: false,
                    message: "Timed out launching \(terminal.displayName). If macOS prompted for Automation permission, approve it in System Settings → Privacy & Security → Automation.",
                    standardOutput: result.stdout,
                    standardError: result.stderr
                )
            }

            if result.exitCode == 0 {
                return LaunchResult(
                    terminal: terminal,
                    layoutName: layoutName,
                    succeeded: true,
                    message: "Launched \"\(layoutName)\" in \(terminal.displayName).",
                    standardOutput: result.stdout,
                    standardError: result.stderr
                )
            } else {
                let detail = result.stderr.isEmpty ? "Process exited with code \(result.exitCode)." : result.stderr
                return LaunchResult(
                    terminal: terminal,
                    layoutName: layoutName,
                    succeeded: false,
                    message: "Could not launch in \(terminal.displayName): \(detail)",
                    standardOutput: result.stdout,
                    standardError: result.stderr
                )
            }
        } catch {
            return LaunchResult(
                terminal: terminal,
                layoutName: layoutName,
                succeeded: false,
                message: "Failed to execute launcher for \(terminal.displayName): \(error.localizedDescription)"
            )
        }
    }
}
