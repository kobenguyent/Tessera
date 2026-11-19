import Foundation
import Testing
@testable import TesseraCore

@Suite("Backend Security & Robustness Hardening")
struct BackendHardeningTests {
    @Test("CommandFormatter enforces strict ASCII POSIX env keys and strips NUL bytes")
    func strictASCIIEnvKeysAndNulStripping() {
        #expect(CommandFormatter.isValidEnvKey("NODE_ENV"))
        #expect(CommandFormatter.isValidEnvKey("_PRIVATE_1"))
        #expect(!CommandFormatter.isValidEnvKey("123_INVALID"))
        #expect(!CommandFormatter.isValidEnvKey("CAFÉ_VAR"))
        #expect(!CommandFormatter.isValidEnvKey("BAD;KEY"))
        #expect(!CommandFormatter.isValidEnvKey("BAD\0KEY"))

        #expect(CommandFormatter.shellSingleQuote("safe\0value") == "'safevalue'")
        #expect(CommandFormatter.appleScriptString("line\0test") == "\"linetest\"")
        #expect(CommandFormatter.yamlDoubleQuote("yaml\0val") == "\"yamlval\"")
        #expect(CommandFormatter.expandTilde("~/work\0dir", homeDirectory: "/Users/dev") == "/Users/dev/workdir")
    }

    @Test("SubprocessRunner drains large stdout (>128 KB) without pipe deadlock")
    func drainsLargeOutputWithoutDeadlock() throws {
        // Generate ~160 KB of output (> typical 64 KB macOS pipe buffer)
        let result = try SubprocessRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-c", "python3 -c 'print(\"A\" * 160000)' 2>/dev/null || yes A | head -n 80000"],
            timeoutSeconds: 10.0
        )
        #expect(!result.timedOut)
        #expect(result.exitCode == 0)
        #expect(result.stdout.count >= 64_000)
    }

    @Test("SubprocessRunner enforces timeout and terminates hung processes cleanly")
    func enforcesTimeoutOnHungProcess() throws {
        let start = Date()
        let result = try SubprocessRunner.run(
            executablePath: "/bin/zsh",
            arguments: ["-c", "sleep 15"],
            timeoutSeconds: 0.4
        )
        let elapsed = Date().timeIntervalSince(start)
        #expect(result.timedOut)
        #expect(result.exitCode == -1)
        #expect(elapsed < 4.0)
    }

    @Test("LayoutStore writes 0600 permissions, quarantines corrupt JSON, and rejects oversized imports")
    func layoutStoreSecurityAndRecovery() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-store-hardening-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storeURL = tempDir.appendingPathComponent("layouts.json")
        let store = LayoutStore(fileURL: storeURL)

        let defaults = BuiltInPresets.makeDefaultLayouts()
        try store.saveLayouts(defaults)

        // Verify owner-only 0600 permissions
        let attrs = try FileManager.default.attributesOfItem(atPath: storeURL.path)
        let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue
        #expect(perms == 0o600)

        // Corrupt the JSON file and verify loadLayouts quarantines a .bak copy instead of losing it
        try Data("{ invalid json".utf8).write(to: storeURL, options: .atomic)
        #expect(throws: Error.self) {
            _ = try store.loadLayouts()
        }
        let entries = try FileManager.default.contentsOfDirectory(atPath: tempDir.path)
        #expect(entries.contains(where: { $0.hasPrefix("layouts.json.corrupt-") && $0.hasSuffix(".bak") }))

        // Oversized import payload rejected cleanly
        let hugeData = Data(count: LayoutStore.maxImportBytes + 1)
        #expect(throws: StorageImportError.self) {
            _ = try store.importJSON(from: hugeData)
        }
    }

    @Test("Built-in presets contain zero AI filler text or sparkle symbols")
    func builtInPresetsAreClean() {
        let presets = BuiltInPresets.makeDefaultLayouts()
        #expect(presets.count == 6)
        for layout in presets {
            #expect(layout.name.range(of: #"\b(AI|Agent)\b"#, options: .regularExpression) == nil)
            #expect(layout.icon != "sparkles")
            for tab in layout.tabs {
                for pane in tab.root.allLeaves {
                    for cmd in pane.commands {
                        #expect(!cmd.contains("✦"))
                    }
                }
            }
        }
    }
}
