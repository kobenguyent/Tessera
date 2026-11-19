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

    public init(
        terminal: TerminalKind,
        layoutName: String,
        summary: String,
        warnings: [String] = [],
        previewTitle: String,
        previewLanguage: String,
        previewContent: String,
        action: LaunchAction
    ) {
        self.terminal = terminal
        self.layoutName = layoutName
        self.summary = summary
        self.warnings = warnings
        self.previewTitle = previewTitle
        self.previewLanguage = previewLanguage
        self.previewContent = previewContent
        self.action = action
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
