import Foundation
import Testing
@testable import TesseraCore

@Suite("Live Script Editor & Custom Overrides")
struct ScriptEditorTests {
    @Test("LaunchPlan.withCustomContent updates AppleScript, Shell, and File-backed actions")
    func withCustomContentPreservesActionType() throws {
        let layout = BuiltInPresets.fullStackFoundry()

        // 1. AppleScript (iTerm2)
        let itermPlan = LaunchPlanBuilder.build(layout: layout, terminal: .iterm2)
        let editedIterm = itermPlan.withCustomContent("tell application id \"com.googlecode.iterm2\" to activate")
        #expect(editedIterm.isCustomScript)
        #expect(editedIterm.previewContent.contains("to activate"))
        guard case .appleScript(let appleScript) = editedIterm.action else {
            Issue.record("Expected .appleScript action")
            return
        }
        #expect(appleScript == editedIterm.previewContent)

        // 2. Shell Script (WezTerm)
        let wezPlan = LaunchPlanBuilder.build(layout: layout, terminal: .wezterm)
        let editedWez = wezPlan.withCustomContent("#!/bin/zsh\necho custom\n")
        guard case .shellScript(let shell) = editedWez.action else {
            Issue.record("Expected .shellScript action")
            return
        }
        #expect(shell.contains("echo custom"))

        // 3. Write File & Run Shell (Warp YAML)
        let ctx = LaunchContext(homeDirectory: "/Users/tester")
        let warpPlan = LaunchPlanBuilder.build(layout: layout, terminal: .warp, context: ctx)
        let customYAML = "---\nname: Custom\nwindows:\n  - tabs: []\n"
        let editedWarp = warpPlan.withCustomContent(customYAML)
        guard case .writeFileAndRunShell(let filePath, let fileContent, let shellCmd) = editedWarp.action else {
            Issue.record("Expected .writeFileAndRunShell action")
            return
        }
        #expect(filePath.hasSuffix("tessera_full-stack-foundry.yaml"))
        #expect(fileContent == customYAML)
        #expect(shellCmd.contains("warp://launch/"))
    }

    @Test("LaunchPlanBuilder applies saved custom script per terminal and respects ignoreCustomScript")
    func builderUsesSavedOverrideUnlessIgnored() {
        var layout = BuiltInPresets.dualFocusPair()
        let customScript = "#!/bin/zsh\necho 'from custom override'\n"
        layout.setCustomScript(customScript, for: .tmux)

        #expect(layout.hasCustomScript(for: .tmux))
        #expect(!layout.hasCustomScript(for: .iterm2))
        #expect(layout.hasAnyCustomScript)

        let tmuxPlan = LaunchPlanBuilder.build(layout: layout, terminal: .tmux)
        #expect(tmuxPlan.isCustomScript)
        #expect(tmuxPlan.previewContent == customScript)

        let regeneratedPlan = LaunchPlanBuilder.build(layout: layout, terminal: .tmux, ignoreCustomScript: true)
        #expect(!regeneratedPlan.isCustomScript)
        #expect(regeneratedPlan.previewContent.contains("new-session -d -s"))

        let itermPlan = LaunchPlanBuilder.build(layout: layout, terminal: .iterm2)
        #expect(!itermPlan.isCustomScript)
    }

    @Test("TesseraLayout decodes legacy JSON missing customScripts cleanly")
    func backwardCompatibleDecoding() throws {
        let legacyJSON = """
        {
          "id": "20000000-0000-4000-8000-000000000001",
          "name": "Legacy Layout",
          "subtitle": "Old schema",
          "icon": "terminal",
          "accentHex": "#6366F1",
          "workingDirectory": "~",
          "windowFrame": "centeredLarge",
          "tabs": [
            {
              "id": "20000000-0000-4000-8000-000000000002",
              "title": "Main",
              "root": {
                "leaf": {
                  "_0": {
                    "id": "20000000-0000-4000-8000-000000000003",
                    "title": "Shell",
                    "commands": ["pwd"],
                    "environment": [],
                    "delaySeconds": 0,
                    "focus": true
                  }
                }
              }
            }
          ],
          "tags": [],
          "isPinned": false,
          "isBuiltIn": false,
          "createdAt": "2026-11-19T10:00:00Z",
          "updatedAt": "2026-11-19T10:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TesseraLayout.self, from: Data(legacyJSON.utf8))
        #expect(decoded.name == "Legacy Layout")
        #expect(decoded.customScripts.isEmpty)
    }

    @Test("ScriptValidator catches syntax errors in Zsh, AppleScript, YAML, and Kitty sessions")
    func scriptValidationChecks() {
        // Zsh valid vs invalid
        let validZsh = ScriptValidator.validateSync(script: "#!/bin/zsh\necho 'hello'\n", language: "zsh")
        #expect(validZsh.isValid)

        let invalidZsh = ScriptValidator.validateSync(script: "#!/bin/zsh\nif true; then\n  echo 'missing fi'\n", language: "zsh")
        #expect(!invalidZsh.isValid)

        // YAML valid vs tab indentation vs missing windows
        let validYAML = ScriptValidator.validateSync(script: "---\nname: Test\nwindows:\n  - tabs: []\n", language: "yaml")
        #expect(validYAML.isValid)

        let tabYAML = ScriptValidator.validateSync(script: "windows:\n\t- tabs: []\n", language: "yaml")
        #expect(!tabYAML.isValid)

        // Kitty session valid vs empty
        let validKitty = ScriptValidator.validateSync(script: "new_tab Dev\nlayout splits\nlaunch\n", language: "conf")
        #expect(validKitty.isValid)

        let emptyScript = ScriptValidator.validateSync(script: "   \n  ", language: "applescript")
        #expect(!emptyScript.isValid)

        // AppleScript valid vs broken
        if FileManager.default.isExecutableFile(atPath: "/usr/bin/osacompile") {
            let validAS = ScriptValidator.validateSync(script: "return 42", language: "applescript")
            #expect(validAS.isValid)

            let brokenAS = ScriptValidator.validateSync(script: "tell application \"Terminal\"\n  set x to (", language: "applescript")
            #expect(!brokenAS.isValid)
        }
    }
}
