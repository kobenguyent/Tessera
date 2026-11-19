import Foundation

public struct ScriptValidationResult: Equatable, Sendable {
    public let isValid: Bool
    public let message: String

    public init(isValid: Bool, message: String) {
        self.isValid = isValid
        self.message = message
    }
}

/// Performs safe, zero-execution syntax checks for edited terminal launch scripts.
public enum ScriptValidator {
    public static func validate(script: String, language: String) async -> ScriptValidationResult {
        await Task.detached(priority: .userInitiated) {
            validateSync(script: script, language: language)
        }.value
    }

    public static func validateSync(script: String, language: String) -> ScriptValidationResult {
        let trimmed = script.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ScriptValidationResult(isValid: false, message: "Script is empty.")
        }

        switch language.lowercased() {
        case "applescript":
            return validateAppleScript(script)
        case "zsh", "bash", "sh":
            return validateZsh(script)
        case "yaml", "yml":
            return validateYAML(script)
        case "conf", "kitty":
            return validateKittySession(script)
        default:
            return ScriptValidationResult(isValid: true, message: "Ready to execute.")
        }
    }

    private static func validateAppleScript(_ script: String) -> ScriptValidationResult {
        let osacompile = "/usr/bin/osacompile"
        guard FileManager.default.isExecutableFile(atPath: osacompile) else {
            return ScriptValidationResult(isValid: true, message: "osacompile unavailable; basic check passed.")
        }

        let tempOut = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-validate-\(UUID().uuidString).scpt")
        defer { try? FileManager.default.removeItem(at: tempOut) }

        return runCheckProcess(
            executablePath: osacompile,
            arguments: ["-o", tempOut.path],
            stdin: script,
            successMessage: "AppleScript compiled with zero syntax errors."
        )
    }

    private static func validateZsh(_ script: String) -> ScriptValidationResult {
        runCheckProcess(
            executablePath: "/bin/zsh",
            arguments: ["-n"],
            stdin: script,
            successMessage: "Zsh syntax check passed."
        )
    }

    private static func validateYAML(_ script: String) -> ScriptValidationResult {
        let lines = script.components(separatedBy: .newlines)
        for (idx, line) in lines.enumerated() {
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty || stripped.hasPrefix("#") || stripped == "---" { continue }
            if line.hasPrefix("\t") || line.prefix(while: { $0 == " " || $0 == "\t" }).contains("\t") {
                return ScriptValidationResult(
                    isValid: false,
                    message: "Line \(idx + 1): YAML indentation cannot contain tab characters — use spaces."
                )
            }
        }
        if !script.contains("windows:") {
            return ScriptValidationResult(
                isValid: false,
                message: "Warp Launch Configuration should define a top-level `windows:` key."
            )
        }
        return ScriptValidationResult(isValid: true, message: "Warp Launch YAML structure looks valid.")
    }

    private static func validateKittySession(_ script: String) -> ScriptValidationResult {
        let lines = script
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        guard !lines.isEmpty else {
            return ScriptValidationResult(isValid: false, message: "Kitty session contains no commands.")
        }
        if !lines.contains(where: { $0.hasPrefix("launch") || $0.hasPrefix("new_tab") }) {
            return ScriptValidationResult(
                isValid: false,
                message: "Kitty session should include at least one `launch` or `new_tab` directive."
            )
        }
        return ScriptValidationResult(isValid: true, message: "Kitty session configuration looks valid.")
    }

    private static func runCheckProcess(
        executablePath: String,
        arguments: [String],
        stdin: String,
        successMessage: String
    ) -> ScriptValidationResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdinPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        do {
            try process.run()
            if let data = stdin.data(using: .utf8) {
                stdinPipe.fileHandleForWriting.write(data)
                try? stdinPipe.fileHandleForWriting.close()
            }
            process.waitUntilExit()

            let stderr = String(
                data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            if process.terminationStatus == 0 {
                return ScriptValidationResult(isValid: true, message: successMessage)
            }
            return ScriptValidationResult(
                isValid: false,
                message: stderr.isEmpty ? "Syntax check failed (exit code \(process.terminationStatus))." : stderr
            )
        } catch {
            return ScriptValidationResult(
                isValid: false,
                message: "Validation failed: \(error.localizedDescription)"
            )
        }
    }
}
