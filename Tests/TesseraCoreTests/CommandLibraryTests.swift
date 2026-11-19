import Foundation
import Testing
@testable import TesseraCore

@Suite("Custom Command Library")
struct CommandLibraryTests {
    @Test("Seeds default commands on first load and persists custom additions")
    func seedsAndPersistsCustomCommands() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-cmd-lib-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = CommandLibraryStore(fileURL: tempDir.appendingPathComponent("commands.json"))
        let seeded = try store.loadCommands()
        #expect(seeded.count >= 5)
        #expect(FileManager.default.fileExists(atPath: store.fileURL.path))

        var updated = seeded
        let custom = CommandSnippet(
            label: "Claude Agent",
            command: "claude --dangerously-skip-permissions",
            category: .custom,
            isBuiltIn: false
        )
        updated.insert(custom, at: 0)
        try store.saveCommands(updated)

        let reloaded = try store.loadCommands()
        #expect(reloaded.count == seeded.count + 1)
        #expect(reloaded.first?.label == "Claude Agent")
        #expect(reloaded.first?.command == "claude --dangerously-skip-permissions")
        #expect(reloaded.first?.category == .custom)
        #expect(reloaded.first?.isBuiltIn == false)
    }

    @Test("Exports and imports both single snippets and snippet arrays")
    func exportAndImportRoundTrip() throws {
        let store = CommandLibraryStore(
            fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("unused-\(UUID().uuidString).json")
        )
        let snippet = CommandSnippet(
            label: "Postgres Up",
            command: "docker compose up -d postgres",
            category: .containers
        )

        let arrayJSON = try store.exportJSON(commands: [snippet])
        let fromArray = try store.importJSON(from: arrayJSON)
        #expect(fromArray.count == 1)
        #expect(fromArray.first?.id == snippet.id)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let singleJSON = try encoder.encode(snippet)
        let fromSingle = try store.importJSON(from: singleJSON)
        #expect(fromSingle.count == 1)
        #expect(fromSingle.first?.label == "Postgres Up")
    }

    @Test("Suggests crisp labels for arbitrary shell commands")
    func suggestedLabelHelper() {
        #expect(CommandSnippet.suggestedLabel(for: "npm run dev -- --port 3000") == "npm run")
        #expect(CommandSnippet.suggestedLabel(for: "   ") == "Custom Command")
        #expect(CommandSnippet.suggestedLabel(for: "kubectl") == "kubectl")
    }
}
