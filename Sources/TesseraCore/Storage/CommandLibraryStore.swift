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
        do {
            return try Self.makeDecoder().decode([CommandSnippet].self, from: data)
        } catch {
            quarantineCorruptFile()
            throw error
        }
    }

    public func saveCommands(_ commands: [CommandSnippet]) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(commands)
        try data.write(to: fileURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    public func exportJSON(commands: [CommandSnippet]) throws -> Data {
        try Self.makeEncoder().encode(commands)
    }

    public func importJSON(from data: Data) throws -> [CommandSnippet] {
        guard data.count <= LayoutStore.maxImportBytes else {
            throw StorageImportError.payloadTooLarge(maxBytes: LayoutStore.maxImportBytes)
        }
        let decoder = Self.makeDecoder()
        if let array = try? decoder.decode([CommandSnippet].self, from: data) {
            return array
        }
        let single = try decoder.decode(CommandSnippet.self, from: data)
        return [single]
    }

    private func quarantineCorruptFile() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let backupURL = fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(fileURL.lastPathComponent).corrupt-\(stamp).bak")
        try? fm.copyItem(at: fileURL, to: backupURL)
        try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
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
