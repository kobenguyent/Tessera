import Foundation
import Testing
@testable import TesseraCore

@Suite("Terminal Adapters & Script Generation")
struct TerminalAdapterTests {
    private func makeRichLayout() -> TesseraLayout {
        let tab1 = TesseraTab(
            title: "Dev",
            root: .split(SplitSpec(
                direction: .columns,
                ratio: 0.6,
                first: .leaf(PaneSpec(
                    title: "Frontend \"App\"",
                    workingDirectory: "~/Projects/my app",
                    commands: ["echo 'hello world'", "npm run dev"],
                    environment: [EnvEntry(key: "PORT", value: "3000")],
                    profile: "Default",
                    focus: true
                )),
                second: .split(SplitSpec(
                    direction: .rows,
                    ratio: 0.4,
                    first: .leaf(PaneSpec(
                        title: "API",
                        commands: ["swift run"],
                        delaySeconds: 1.5
                    )),
                    second: .leaf(PaneSpec(
                        title: "Logs",
                        commands: ["tail -f /tmp/app.log"]
                    ))
                ))
            ))
        )

        let tab2 = TesseraTab(
            title: "Ops",
            root: .leaf(PaneSpec(title: "Cluster", commands: ["uptime"]))
        )

        return TesseraLayout(
            name: "Full Stack Demo",
            workingDirectory: "~/workspace",
            windowFrame: .centeredLarge,
            tabs: [tab1, tab2]
        )
    }

    @Test("CommandFormatter safely escapes shell quotes, AppleScript strings, and env keys")
    func commandFormatterEscaping() {
        #expect(CommandFormatter.shellSingleQuote("it's ok") == "'it'\\''s ok'")
        #expect(CommandFormatter.appleScriptString("say \"hi\"\\n") == "\"say \\\"hi\\\"\\\\n\"")
        #expect(CommandFormatter.isValidEnvKey("NODE_ENV"))
        #expect(!CommandFormatter.isValidEnvKey("1BAD;rm -rf"))

        let pane = PaneSpec(
            title: "API",
            commands: ["echo 'ok'", "ls -la"],
            environment: [
                EnvEntry(key: "API_PORT", value: "8080"),
                EnvEntry(key: "INVALID-KEY", value: "ignored")
            ],
            delaySeconds: 1.5
        )
        let cmd = CommandFormatter.buildPaneCommandLine(pane: pane, workingDirectory: "~/my dir", includeCD: true)
        #expect(cmd.contains("cd \"$HOME\"/'my dir'"))
        #expect(cmd.contains("export API_PORT='8080'"))
        #expect(!cmd.contains("INVALID-KEY"))
        #expect(cmd.contains("sleep 1.5"))
        #expect(cmd.contains("echo 'ok' ; ls -la"))
    }

    @Test("iTerm2 adapter emits splits, tabs, profile, bounds, and focus selection")
    func iTerm2Adapter() {
        let plan = LaunchPlanBuilder.build(layout: makeRichLayout(), terminal: .iterm2)

        #expect(plan.terminal == .iterm2)
        #expect(plan.previewLanguage == "applescript")
        #expect(plan.previewContent.contains("tell application id \"com.googlecode.iterm2\""))
        #expect(plan.previewContent.contains("create window with profile \"Default\""))
        #expect(plan.previewContent.contains("split vertically with default profile"))
        #expect(plan.previewContent.contains("split horizontally with default profile"))
        #expect(plan.previewContent.contains("create tab with default profile"))
        #expect(plan.previewContent.contains("set bounds of targetWindow to"))
        #expect(plan.previewContent.contains("select sess_0"))
    }

    @Test("Apple Terminal adapter generates geometric tiled window mosaic")
    func appleTerminalAdapter() {
        let plan = LaunchPlanBuilder.build(layout: makeRichLayout(), terminal: .appleTerminal)

        #expect(plan.terminal == .appleTerminal)
        #expect(plan.previewContent.contains("tell application id \"com.apple.Terminal\""))
        #expect(plan.previewContent.contains("set bounds of termWin_0 to"))
        #expect(plan.previewContent.contains("set bounds of termWin_3 to"))
        #expect(!plan.warnings.isEmpty)
    }

    @Test("Warp adapter emits launch configuration YAML and warp://launch URI")
    func warpAdapter() throws {
        let ctx = LaunchContext(homeDirectory: "/Users/tester")
        let plan = LaunchPlanBuilder.build(layout: makeRichLayout(), terminal: .warp, context: ctx)

        #expect(plan.terminal == .warp)
        #expect(plan.previewLanguage == "yaml")
        #expect(plan.previewContent.contains("split_direction: horizontal"))
        #expect(plan.previewContent.contains("split_direction: vertical"))
        #expect(plan.previewContent.contains("is_focused: true"))
        #expect(plan.previewContent.contains("/Users/tester/Projects/my app"))

        guard case .writeFileAndRunShell(let path, _, let shell) = plan.action else {
            Issue.record("Expected writeFileAndRunShell action for Warp")
            return
        }
        #expect(path == "/Users/tester/.warp/launch_configurations/tessera_full-stack-demo.yaml")
        #expect(shell.contains("warp://launch/tessera_full-stack-demo.yaml"))
    }

    @Test("WezTerm adapter emits exact split percentages via wezterm cli")
    func wezTermAdapter() {
        let plan = LaunchPlanBuilder.build(layout: makeRichLayout(), terminal: .wezterm)

        #expect(plan.previewContent.contains("wezterm"))
        #expect(plan.previewContent.contains("cli split-pane"))
        #expect(plan.previewContent.contains("--right --percent 40"))
        #expect(plan.previewContent.contains("--bottom --percent 60"))
        #expect(plan.previewContent.contains("cli activate-pane"))
    }

    @Test("Kitty adapter emits native splits session configuration")
    func kittyAdapter() {
        let ctx = LaunchContext(homeDirectory: "/Users/tester")
        let plan = LaunchPlanBuilder.build(layout: makeRichLayout(), terminal: .kitty, context: ctx)

        #expect(plan.previewContent.contains("layout splits"))
        #expect(plan.previewContent.contains("--location=vsplit"))
        #expect(plan.previewContent.contains("--location=hsplit"))
        #expect(plan.previewContent.contains("new_tab Ops"))
        #expect(plan.previewContent.contains("env PORT=3000"))
    }

    @Test("Ghostty, Alacritty, and tmux adapters generate valid orchestration scripts")
    func ghosttyAlacrittyAndTmuxAdapters() {
        let layout = makeRichLayout()

        let ghostty = LaunchPlanBuilder.build(layout: layout, terminal: .ghostty)
        #expect(ghostty.previewContent.contains("open -na Ghostty --args"))
        #expect(ghostty.previewContent.contains("--working-directory="))

        let alacritty = LaunchPlanBuilder.build(layout: layout, terminal: .alacritty)
        #expect(alacritty.previewContent.contains("window.position.x="))
        #expect(alacritty.previewContent.contains("window.dimensions.columns="))

        let tmux = LaunchPlanBuilder.build(layout: layout, terminal: .tmux)
        #expect(tmux.previewContent.contains("new-session -d -s"))
        #expect(tmux.previewContent.contains("split-window -h -l 40%"))
        #expect(tmux.previewContent.contains("split-window -v -l 60%"))
        #expect(tmux.previewContent.contains("attach-session"))
    }

    @Test("Every built-in preset builds cleanly across all 8 supported terminals")
    func allBuiltInPresetsBuildForEveryTerminal() {
        let presets = BuiltInPresets.makeDefaultLayouts()
        #expect(presets.count >= 5)
        for preset in presets {
            for terminal in TerminalKind.allCases {
                let plan = LaunchPlanBuilder.build(layout: preset, terminal: terminal)
                #expect(!plan.previewContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    @Test("Generated AppleScripts compile cleanly with macOS osacompile")
    func generatedAppleScriptsCompileWithOsacompile() throws {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/osacompile") else { return }

        let detector = TerminalDetector()
        let layout = makeRichLayout()

        if detector.detect(.appleTerminal).isInstalled {
            let plan = LaunchPlanBuilder.build(layout: layout, terminal: .appleTerminal)
            try verifyAppleScriptSyntax(plan.previewContent)
        }

        if detector.detect(.iterm2).isInstalled {
            let plan = LaunchPlanBuilder.build(layout: layout, terminal: .iterm2)
            try verifyAppleScriptSyntax(plan.previewContent)
        }
    }

    private func verifyAppleScriptSyntax(_ script: String) throws {
        let tempOut = FileManager.default.temporaryDirectory
            .appendingPathComponent("tessera-test-\(UUID().uuidString).scpt")
        defer { try? FileManager.default.removeItem(at: tempOut) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osacompile")
        process.arguments = ["-o", tempOut.path]

        let stdinPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardError = stderrPipe

        try process.run()
        if let data = script.data(using: .utf8) {
            stdinPipe.fileHandleForWriting.write(data)
            try? stdinPipe.fileHandleForWriting.close()
        }
        process.waitUntilExit()

        let errText = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        #expect(process.terminationStatus == 0, "osacompile failed: \(errText)")
    }
}
