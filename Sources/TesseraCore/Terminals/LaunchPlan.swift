import Foundation

public enum LaunchAction: Equatable, Sendable {
    case appleScript(String)
    case shellScript(String)
    case writeFileAndRunShell(filePath: String, fileContent: String, shellCommand: String)
}

public struct LaunchPlan: Equatable, Sendable {
    public let terminal: TerminalKind
    public let layoutName: String
    public let summary: String
    public let warnings: [String]
    public let previewTitle: String
    public let previewLanguage: String
    public let previewContent: String
    public let action: LaunchAction
    public let isCustomScript: Bool

    public init(
        terminal: TerminalKind,
        layoutName: String,
        summary: String,
        warnings: [String] = [],
        previewTitle: String,
        previewLanguage: String,
        previewContent: String,
        action: LaunchAction,
        isCustomScript: Bool = false
    ) {
        self.terminal = terminal
        self.layoutName = layoutName
        self.summary = summary
        self.warnings = warnings
        self.previewTitle = previewTitle
        self.previewLanguage = previewLanguage
        self.previewContent = previewContent
        self.action = action
        self.isCustomScript = isCustomScript
    }

    /// Returns a copy of this launch plan whose executable payload is replaced with `editedContent`.
    public func withCustomContent(_ editedContent: String, isCustomScript: Bool = true) -> LaunchPlan {
        let updatedAction: LaunchAction
        switch action {
        case .appleScript:
            updatedAction = .appleScript(editedContent)
        case .shellScript:
            updatedAction = .shellScript(editedContent)
        case .writeFileAndRunShell(let filePath, _, let shellCommand):
            updatedAction = .writeFileAndRunShell(
                filePath: filePath,
                fileContent: editedContent,
                shellCommand: shellCommand
            )
        }

        return LaunchPlan(
            terminal: terminal,
            layoutName: layoutName,
            summary: isCustomScript ? "Runs custom edited \(terminal.displayName) script." : summary,
            warnings: warnings,
            previewTitle: previewTitle,
            previewLanguage: previewLanguage,
            previewContent: editedContent,
            action: updatedAction,
            isCustomScript: isCustomScript
        )
    }
}

public struct LaunchResult: Equatable, Sendable {
    public let terminal: TerminalKind
    public let layoutName: String
    public let succeeded: Bool
    public let message: String
    public let standardOutput: String
    public let standardError: String

    public init(
        terminal: TerminalKind,
        layoutName: String,
        succeeded: Bool,
        message: String,
        standardOutput: String = "",
        standardError: String = ""
    ) {
        self.terminal = terminal
        self.layoutName = layoutName
        self.succeeded = succeeded
        self.message = message
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}
