import Foundation
import Testing
@testable import TesseraCore

@Suite("Layout & Settings Persistence")
struct LayoutStoreTests {
    @Test("Seeds default presets on first launch and round-trips JSON export/import")
    func seedsDefaultsAndRoundTripsJSON() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = LayoutStore(fileURL: tempDir.appendingPathComponent("layouts.json"))
        let seeded = try store.loadLayouts()
        #expect(seeded.count >= 5)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))

        var custom = seeded
        let extra = TesseraLayout(
            name: "Custom Lab",
            subtitle: "Testing round-trip",
            preferredTerminal: .wezterm,
            workingDirectory: "~/lab",
            tabs: [TesseraTab(title: "Main", root: MosaicStructureTemplate.sideBySide.makeTree())]
        )
        custom.append(extra)
        try store.saveLayouts(custom)

        let reloaded = try store.loadLayouts()
        #expect(reloaded.count == custom.count)
        #expect(reloaded.last?.name == "Custom Lab")
        #expect(reloaded.last?.preferredTerminal == .wezterm)

        let exportedArray = try store.exportJSON(layouts: [extra])
        let importedArray = try store.importJSON(from: exportedArray)
        #expect(importedArray.first?.id == extra.id)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let singleData = try encoder.encode(extra)
        let importedSingle = try store.importJSON(from: singleData)
        #expect(importedSingle.count == 1)
        #expect(importedSingle.first?.name == "Custom Lab")
    }

    @Test("Scheduled auto-update check honors interval and enabled flag")
    func scheduledUpdateCheckRespectsInterval() {
        var settings = AppSettings(autoCheckForUpdates: true, updateCheckIntervalHours: 24, lastUpdateCheckDate: nil)
        #expect(settings.shouldRunScheduledUpdateCheck())

        let now = Date()
        settings.lastUpdateCheckDate = now.addingTimeInterval(-3600)
        #expect(!settings.shouldRunScheduledUpdateCheck(now: now))

        settings.lastUpdateCheckDate = now.addingTimeInterval(-25 * 3600)
        #expect(settings.shouldRunScheduledUpdateCheck(now: now))

        settings.autoCheckForUpdates = false
        #expect(!settings.shouldRunScheduledUpdateCheck(now: now))
    }
}
