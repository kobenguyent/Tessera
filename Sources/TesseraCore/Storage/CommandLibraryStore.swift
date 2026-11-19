import Foundation

public struct CommandLibraryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = CommandLibraryStore.defaultFileURL()
        }
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Tessera", isDirectory: true)
            .appendingPathComponent("commands.json")
    }

    public func loadCommands() throws -> [CommandSnippet] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            let defaults = CommandSnippet.builtInDefaults()
            try? saveCommands(defaults)
            return defaults
        }

        let data = try Data(contentsOf: fileURL)
        return try Self.makeDecoder().decode([CommandSnippet].self, from: data)
    }

    public func saveCommands(_ commands: [CommandSnippet]) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(commands)
        try data.write(to: fileURL, options: .atomic)
    }

    public func exportJSON(commands: [CommandSnippet]) throws -> Data {
        try Self.makeEncoder().encode(commands)
    }

    public func importJSON(from data: Data) throws -> [CommandSnippet] {
        let decoder = Self.makeDecoder()
        if let array = try? decoder.decode([CommandSnippet].self, from: data) {
            return array
        }
        let single = try decoder.decode(CommandSnippet.self, from: data)
        return [single]
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
