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
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        let stdinPipe = Pipe()
        if stdin != nil {
            process.standardInput = stdinPipe
        }

        do {
            try process.run()
            if let stdin, let data = stdin.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
                try? stdinPipe.fileHandleForWriting.close()
            }
            process.waitUntilExit()

            let outData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
            let stdout = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let stderr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0 {
                return LaunchResult(
                    terminal: terminal,
                    layoutName: layoutName,
                    succeeded: true,
                    message: "Launched \"\(layoutName)\" in \(terminal.displayName).",
                    standardOutput: stdout,
                    standardError: stderr
                )
            } else {
                let detail = stderr.isEmpty ? "Process exited with code \(process.terminationStatus)." : stderr
                return LaunchResult(
                    terminal: terminal,
                    layoutName: layoutName,
                    succeeded: false,
                    message: "Could not launch in \(terminal.displayName): \(detail)",
                    standardOutput: stdout,
                    standardError: stderr
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
