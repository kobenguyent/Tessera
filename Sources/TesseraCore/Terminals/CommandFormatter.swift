import Foundation

public enum CommandFormatter {
    /// Expands a leading `~` to the user's home directory.
    public static func expandTilde(_ path: String, homeDirectory: String = NSHomeDirectory()) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == "~" {
            return homeDirectory
        }
        if trimmed.hasPrefix("~/") {
            return homeDirectory + String(trimmed.dropFirst(1))
        }
        return trimmed
    }

    /// Wraps a string in POSIX single quotes, safely escaping embedded single quotes.
    public static func shellSingleQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Escapes a string for embedding inside an AppleScript double-quoted literal.
    public static func appleScriptString(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count + 8)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped.append("\\\\")
            case "\"": escaped.append("\\\"")
            case "\n": escaped.append("\\n")
            case "\r": escaped.append("\\r")
            case "\t": escaped.append("\\t")
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"" + escaped + "\""
    }

    /// Escapes a string for a YAML double-quoted scalar.
    public static func yamlDoubleQuote(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count + 8)
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\\": escaped.append("\\\\")
            case "\"": escaped.append("\\\"")
            case "\n": escaped.append("\\n")
            case "\r": escaped.append("\\r")
            case "\t": escaped.append("\\t")
            default: escaped.unicodeScalars.append(scalar)
            }
        }
        return "\"" + escaped + "\""
    }

    /// Validates POSIX shell environment variable names.
    public static func isValidEnvKey(_ key: String) -> Bool {
        guard let first = key.unicodeScalars.first else { return false }
        let startSet = CharacterSet.letters.union(CharacterSet(charactersIn: "_"))
        let bodySet = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        guard startSet.contains(first) else { return false }
        return key.unicodeScalars.dropFirst().allSatisfy { bodySet.contains($0) }
    }

    /// Formats a `cd` command for the given working directory, preserving `$HOME` expansion for `~`.
    public static func cdCommand(for workingDirectory: String) -> String? {
        let trimmed = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed == "~" {
            return "cd \"$HOME\""
        }
        if trimmed.hasPrefix("~/") {
            let suffix = String(trimmed.dropFirst(2))
            return "cd \"$HOME\"/\(shellSingleQuote(suffix))"
        }
        return "cd \(shellSingleQuote(trimmed))"
    }

    /// Builds the full single-line command sent to an interactive terminal pane.
    public static func buildPaneCommandLine(
        pane: PaneSpec,
        workingDirectory: String,
        includeCD: Bool = true
    ) -> String {
        var setupParts: [String] = []

        if includeCD, let cdCmd = cdCommand(for: workingDirectory) {
            setupParts.append(cdCmd)
        }

        for entry in pane.environment {
            let key = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isValidEnvKey(key) else { continue }
            setupParts.append("export \(key)=\(shellSingleQuote(entry.value))")
        }

        if pane.delaySeconds > 0 {
            let formatted = String(format: "%.2f", pane.delaySeconds)
                .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
            setupParts.append("sleep \(formatted)")
        }

        let userCommands = pane.nonEmptyCommands
        let setupSegment = setupParts.joined(separator: " && ")

        if userCommands.isEmpty {
            return setupSegment
        }

        let commandSegment: String
        if userCommands.count == 1 {
            commandSegment = userCommands[0]
        } else {
            commandSegment = "{ \(userCommands.joined(separator: " ; ")); }"
        }
        if setupSegment.isEmpty {
            return userCommands.joined(separator: " ; ")
        }
        return "\(setupSegment) && \(commandSegment)"
    }

    /// Wraps a command for direct `-e /bin/zsh -lc ...` launchers so the terminal stays interactive afterward.
    public static func interactiveShellPayload(command: String) -> String {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "exec \"${SHELL:-/bin/zsh}\" -l"
        }
        return "\(trimmed); exec \"${SHELL:-/bin/zsh}\" -l"
    }
}
