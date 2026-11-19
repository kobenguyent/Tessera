import Foundation

public struct AppSettings: Codable, Equatable, Sendable {
    public var defaultTerminal: TerminalKind
    public var githubRepository: String
    public var autoCheckForUpdates: Bool
    public var updateCheckIntervalHours: Double
    public var includePrereleases: Bool
    public var skippedVersion: String?
    public var lastUpdateCheckDate: Date?

    public init(
        defaultTerminal: TerminalKind = .iterm2,
        githubRepository: String = TesseraMetadata.bundledGitHubRepository,
        autoCheckForUpdates: Bool = true,
        updateCheckIntervalHours: Double = 24,
        includePrereleases: Bool = false,
        skippedVersion: String? = nil,
        lastUpdateCheckDate: Date? = nil
    ) {
        self.defaultTerminal = defaultTerminal
        self.githubRepository = githubRepository
        self.autoCheckForUpdates = autoCheckForUpdates
        self.updateCheckIntervalHours = max(1, updateCheckIntervalHours)
        self.includePrereleases = includePrereleases
        self.skippedVersion = skippedVersion
        self.lastUpdateCheckDate = lastUpdateCheckDate
    }

    public func shouldRunScheduledUpdateCheck(now: Date = Date()) -> Bool {
        guard autoCheckForUpdates else { return false }
        guard let lastCheck = lastUpdateCheckDate else { return true }
        return now.timeIntervalSince(lastCheck) >= updateCheckIntervalHours * 3600.0
    }
}

public struct SettingsStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            self.fileURL = base
                .appendingPathComponent("Tessera", isDirectory: true)
                .appendingPathComponent("settings.json")
        }
    }

    public func load(detector: TerminalDetecting = TerminalDetector()) -> AppSettings {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL) else {
            return AppSettings(defaultTerminal: detector.recommendedDefaultTerminal())
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode(AppSettings.self, from: data) {
            return decoded
        }
        return AppSettings(defaultTerminal: detector.recommendedDefaultTerminal())
    }

    public func save(_ settings: AppSettings) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(settings)
        try data.write(to: fileURL, options: .atomic)
    }
}
