import Foundation

public struct LayoutStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            self.fileURL = LayoutStore.defaultFileURL()
        }
    }

    public static func defaultFileURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Tessera", isDirectory: true)
            .appendingPathComponent("layouts.json")
    }

    public func loadLayouts() throws -> [TesseraLayout] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: fileURL.path) else {
            let defaults = BuiltInPresets.makeDefaultLayouts()
            try? saveLayouts(defaults)
            return defaults
        }

        let data = try Data(contentsOf: fileURL)
        let decoder = Self.makeDecoder()
        let layouts = try decoder.decode([TesseraLayout].self, from: data)
        if layouts.isEmpty {
            return BuiltInPresets.makeDefaultLayouts()
        }
        return layouts
    }

    public func saveLayouts(_ layouts: [TesseraLayout]) throws {
        let parent = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let encoder = Self.makeEncoder()
        let data = try encoder.encode(layouts)
        try data.write(to: fileURL, options: .atomic)
    }

    public func exportJSON(layouts: [TesseraLayout]) throws -> Data {
        try Self.makeEncoder().encode(layouts)
    }

    public func importJSON(from data: Data) throws -> [TesseraLayout] {
        let decoder = Self.makeDecoder()
        if let array = try? decoder.decode([TesseraLayout].self, from: data) {
            return array
        }
        let single = try decoder.decode(TesseraLayout.self, from: data)
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
