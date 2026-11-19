import Foundation

public struct LaunchContext: Sendable {
    public let screenBounds: TesseraRect
    public let homeDirectory: String
    public let hostTerminalForTmux: TerminalKind

    public init(
        screenBounds: TesseraRect = TesseraRect(x: 0, y: 25, width: 1512, height: 957),
        homeDirectory: String = NSHomeDirectory(),
        hostTerminalForTmux: TerminalKind = .iterm2
    ) {
        self.screenBounds = screenBounds
        self.homeDirectory = homeDirectory
        self.hostTerminalForTmux = hostTerminalForTmux
    }
}

/// Builds executable `LaunchPlan`s for all 8 supported terminals.
public enum LaunchPlanBuilder {
    public static func build(
        layout: TesseraLayout,
        terminal: TerminalKind,
        context: LaunchContext = LaunchContext()
    ) -> LaunchPlan {
        switch terminal {
        case .iterm2:
            return buildITerm2Plan(layout: layout, context: context)
        case .appleTerminal:
            return buildAppleTerminalPlan(layout: layout, context: context)
        case .warp:
            return buildWarpPlan(layout: layout, context: context)
        case .wezterm:
            return buildWezTermPlan(layout: layout, context: context)
        case .kitty:
            return buildKittyPlan(layout: layout, context: context)
        case .ghostty:
            return buildGhosttyPlan(layout: layout, context: context)
        case .alacritty:
            return buildAlacrittyPlan(layout: layout, context: context)
        case .tmux:
            return buildTmuxPlan(layout: layout, context: context)
        }
    }

    // MARK: - 1. iTerm2 (Full Native Splits, Tabs, Profiles, Bounds & Focus)

    private static func buildITerm2Plan(layout: TesseraLayout, context: LaunchContext) -> LaunchPlan {
        var lines: [String] = []
        lines.append("-- Tessera Mosaic: \(layout.name)")
        lines.append("tell application id \"com.googlecode.iterm2\"")
        lines.append("    activate")

        var sessionCounter = 0
        func nextSessionVar() -> String {
            defer { sessionCounter += 1 }
            return "sess_\(sessionCounter)"
        }

        func profileClause(for pane: PaneSpec) -> String {
            if let profile = pane.profile?.trimmingCharacters(in: .whitespacesAndNewlines), !profile.isEmpty {
                return "with profile \(CommandFormatter.appleScriptString(profile))"
            }
            return "with default profile"
        }

        var focusSessionVar: String?
        var focusTabVar: String?

        func emitNode(_ node: PaneNode, sessionVar: String, tabVar: String) {
            switch node {
            case .leaf(let pane):
                let cwd = layout.effectiveWorkingDirectory(for: pane)
                let cmd = CommandFormatter.buildPaneCommandLine(pane: pane, workingDirectory: cwd, includeCD: true)
                lines.append("    tell \(sessionVar)")
                if !pane.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("        set name to \(CommandFormatter.appleScriptString(pane.title))")
                }
                if !cmd.isEmpty {
                    lines.append("        write text \(CommandFormatter.appleScriptString(cmd))")
                }
                lines.append("    end tell")
                if pane.focus, focusSessionVar == nil {
                    focusSessionVar = sessionVar
                    focusTabVar = tabVar
                }
            case .split(let split):
                let secondVar = nextSessionVar()
                let splitVerb = split.direction == .columns ? "split vertically" : "split horizontally"
                let clause = profileClause(for: split.second.firstLeaf)
                lines.append("    tell \(sessionVar)")
                lines.append("        set \(secondVar) to (\(splitVerb) \(clause))")
                lines.append("    end tell")
                emitNode(split.first, sessionVar: sessionVar, tabVar: tabVar)
                emitNode(split.second, sessionVar: secondVar, tabVar: tabVar)
            }
        }

        for (index, tab) in layout.tabs.enumerated() {
            let tabVar = "tab_\(index)"
            let rootSessionVar = nextSessionVar()
            let initialProfile = profileClause(for: tab.root.firstLeaf)

            if index == 0 {
                lines.append("    set targetWindow to (create window \(initialProfile))")
                if let bounds = layout.windowFrame.resolveRect(screen: context.screenBounds) {
                    let x1 = Int(bounds.x.rounded())
                    let y1 = Int(bounds.y.rounded())
                    let x2 = Int(bounds.maxX.rounded())
                    let y2 = Int(bounds.maxY.rounded())
                    lines.append("    try")
                    lines.append("        set bounds of targetWindow to {\(x1), \(y1), \(x2), \(y2)}")
                    lines.append("    end try")
                }
                lines.append("    set \(tabVar) to current tab of targetWindow")
            } else {
                lines.append("    tell targetWindow")
                lines.append("        set \(tabVar) to (create tab \(initialProfile))")
                lines.append("    end tell")
            }

            lines.append("    set \(rootSessionVar) to current session of \(tabVar)")
            emitNode(tab.root, sessionVar: rootSessionVar, tabVar: tabVar)
        }

        if let focusTab = focusTabVar {
            lines.append("    try")
            lines.append("        select \(focusTab)")
            lines.append("    end try")
        }
        if let focusSess = focusSessionVar {
            lines.append("    try")
            lines.append("        select \(focusSess)")
            lines.append("    end try")
        }

        lines.append("end tell")
        let script = lines.joined(separator: "\n")

        return LaunchPlan(
            terminal: .iterm2,
            layoutName: layout.name,
            summary: "Creates \(layout.tabs.count) tab(s) and \(layout.totalPaneCount) split pane(s) natively in iTerm2.",
            previewTitle: "iTerm2 AppleScript",
            previewLanguage: "applescript",
            previewContent: script,
            action: .appleScript(script)
        )
    }

    // MARK: - 2. Apple Terminal (Precision Geometric Window Mosaic)

    private static func buildAppleTerminalPlan(layout: TesseraLayout, context: LaunchContext) -> LaunchPlan {
        let containerRect = layout.windowFrame.resolveRect(screen: context.screenBounds)
            ?? WindowFramePreset.centeredLarge.resolveRect(screen: context.screenBounds)
            ?? context.screenBounds

        var lines: [String] = []
        lines.append("-- Tessera Mosaic (Apple Terminal Geometric Tiling): \(layout.name)")
        lines.append("tell application id \"com.apple.Terminal\"")
        lines.append("    activate")

        var paneIndex = 0
        var focusedWindowVar: String?

        for (tabIdx, tab) in layout.tabs.enumerated() {
            // Slight cascade offset for additional tabs so multiple tabs stay discoverable
            let cascadeOffset = Double(tabIdx) * 26.0
            let tabBounds = TesseraRect(
                x: containerRect.x + cascadeOffset,
                y: containerRect.y + cascadeOffset,
                width: max(360, containerRect.width - cascadeOffset),
                height: max(260, containerRect.height - cascadeOffset)
            )
            let frames = LayoutGeometry.computeFrames(root: tab.root, in: tabBounds, gap: 8)

            for frame in frames {
                let pane = frame.pane
                let cwd = layout.effectiveWorkingDirectory(for: pane)
                let cmd = CommandFormatter.buildPaneCommandLine(pane: pane, workingDirectory: cwd, includeCD: true)
                let tabVar = "termTab_\(paneIndex)"
                let winVar = "termWin_\(paneIndex)"
                let title = layout.tabs.count > 1 ? "\(tab.title) · \(pane.title)" : pane.title

                lines.append("    set \(tabVar) to do script \(CommandFormatter.appleScriptString(cmd))")
                lines.append("    set \(winVar) to front window")
                lines.append("    try")
                lines.append("        set custom title of \(tabVar) to \(CommandFormatter.appleScriptString(title))")
                lines.append("        set title displays custom title of \(tabVar) to true")
                if let profile = pane.profile?.trimmingCharacters(in: .whitespacesAndNewlines), !profile.isEmpty {
                    lines.append("        set current settings of \(tabVar) to settings set \(CommandFormatter.appleScriptString(profile))")
                }
                let x1 = Int(frame.rect.x.rounded())
                let y1 = Int(frame.rect.y.rounded())
                let x2 = Int(frame.rect.maxX.rounded())
                let y2 = Int(frame.rect.maxY.rounded())
                lines.append("        set bounds of \(winVar) to {\(x1), \(y1), \(x2), \(y2)}")
                lines.append("    end try")

                if pane.focus, focusedWindowVar == nil {
                    focusedWindowVar = winVar
                }
                paneIndex += 1
            }
        }

        if let focusWin = focusedWindowVar {
            lines.append("    try")
            lines.append("        set index of \(focusWin) to 1")
            lines.append("    end try")
        }

        lines.append("end tell")
        let script = lines.joined(separator: "\n")

        var warnings: [String] = []
        if layout.totalPaneCount > 1 {
            warnings.append("Apple Terminal does not support scripted split panes; Tessera arranges your \(layout.totalPaneCount) panes as a precision-tiled window mosaic.")
        }

        return LaunchPlan(
            terminal: .appleTerminal,
            layoutName: layout.name,
            summary: "Tiles \(layout.totalPaneCount) Apple Terminal window(s) into your exact mosaic geometry.",
            warnings: warnings,
            previewTitle: "Apple Terminal AppleScript",
            previewLanguage: "applescript",
            previewContent: script,
            action: .appleScript(script)
        )
    }

    // MARK: - 3. Warp (Native Launch Configuration YAML + warp://launch URI)

    private static func buildWarpPlan(layout: TesseraLayout, context: LaunchContext) -> LaunchPlan {
        let filename = "tessera_\(layout.slug).yaml"
        let configDir = "\(context.homeDirectory)/.warp/launch_configurations"
        let filePath = "\(configDir)/\(filename)"

        var yaml: [String] = []
        yaml.append("# Generated by Tessera — \(layout.name)")
        yaml.append("---")
        yaml.append("name: \(CommandFormatter.yamlDoubleQuote("Tessera - \(layout.name)"))")
        yaml.append("windows:")
        yaml.append("  - tabs:")

        func emitWarpNode(_ node: PaneNode, indent: Int) {
            let pad = String(repeating: " ", count: indent)
            switch node {
            case .leaf(let pane):
                let cwd = CommandFormatter.expandTilde(
                    layout.effectiveWorkingDirectory(for: pane),
                    homeDirectory: context.homeDirectory
                )
                yaml.append("\(pad)- cwd: \(CommandFormatter.yamlDoubleQuote(cwd))")
                if pane.focus {
                    yaml.append("\(pad)  is_focused: true")
                }
                let cmdLine = CommandFormatter.buildPaneCommandLine(pane: pane, workingDirectory: cwd, includeCD: false)
                if !cmdLine.isEmpty {
                    yaml.append("\(pad)  commands:")
                    yaml.append("\(pad)    - exec: \(CommandFormatter.yamlDoubleQuote(cmdLine))")
                }
            case .split(let split):
                // In Warp Launch YAML: horizontal = left|right columns, vertical = top/bottom rows.
                let direction = split.direction == .columns ? "horizontal" : "vertical"
                yaml.append("\(pad)- split_direction: \(direction)")
                yaml.append("\(pad)  panes:")
                emitWarpNode(split.first, indent: indent + 4)
                emitWarpNode(split.second, indent: indent + 4)
            }
        }

        for tab in layout.tabs {
            yaml.append("      - title: \(CommandFormatter.yamlDoubleQuote(tab.title))")
            yaml.append("        layout:")
            switch tab.root {
            case .leaf(let pane):
                let cwd = CommandFormatter.expandTilde(
                    layout.effectiveWorkingDirectory(for: pane),
                    homeDirectory: context.homeDirectory
                )
                yaml.append("          cwd: \(CommandFormatter.yamlDoubleQuote(cwd))")
                if pane.focus {
                    yaml.append("          is_focused: true")
                }
                let cmdLine = CommandFormatter.buildPaneCommandLine(pane: pane, workingDirectory: cwd, includeCD: false)
                if !cmdLine.isEmpty {
                    yaml.append("          commands:")
                    yaml.append("            - exec: \(CommandFormatter.yamlDoubleQuote(cmdLine))")
                }
            case .split(let split):
                let direction = split.direction == .columns ? "horizontal" : "vertical"
                yaml.append("          split_direction: \(direction)")
                yaml.append("          panes:")
                emitWarpNode(split.first, indent: 12)
                emitWarpNode(split.second, indent: 12)
            }
        }

        let yamlContent = yaml.joined(separator: "\n") + "\n"
        let launchURI = "warp://launch/\(filename)"
        let shellCommand = "open \(CommandFormatter.shellSingleQuote(launchURI))"

        return LaunchPlan(
            terminal: .warp,
            layoutName: layout.name,
            summary: "Writes Warp Launch Configuration (\(filename)) and opens via warp://launch.",
            previewTitle: "Warp Launch Configuration (\(filename))",
            previewLanguage: "yaml",
            previewContent: yamlContent,
            action: .writeFileAndRunShell(
                filePath: filePath,
                fileContent: yamlContent,
                shellCommand: shellCommand
            )
        )
    }

    // MARK: - 4. WezTerm (Native Splits with Exact Percentages via wezterm cli)

    private static func buildWezTermPlan(layout: TesseraLayout, context: LaunchContext) -> LaunchPlan {
        var lines: [String] = []
        lines.append("#!/bin/zsh")
        lines.append("set -euo pipefail")
        lines.append("# Tessera Mosaic for WezTerm: \(layout.name)")
        lines.append("WEZTERM_BIN=\"$(command -v wezterm || echo '/Applications/WezTerm.app/Contents/MacOS/wezterm')\"")
        lines.append("if [[ ! -x \"$WEZTERM_BIN\" ]]; then echo 'WezTerm CLI not found' >&2; exit 1; fi")
        lines.append("open -a WezTerm >/dev/null 2>&1 || true")
        lines.append("sleep 0.4")

        var paneCounter = 0
        func nextVar() -> String {
            defer { paneCounter += 1 }
            return "PANE_\(paneCounter)"
        }

        var focusVar: String?

        func emitNode(_ node: PaneNode, paneVar: String) {
            switch node {
            case .leaf(let pane):
                let cwd = layout.effectiveWorkingDirectory(for: pane)
                let cmd = CommandFormatter.buildPaneCommandLine(pane: pane, workingDirectory: cwd, includeCD: false)
                if !cmd.isEmpty {
                    lines.append("printf '%s\\n' \(CommandFormatter.shellSingleQuote(cmd)) | \"$WEZTERM_BIN\" cli send-text --pane-id \"$\(paneVar)\" --no-paste")
                }
                if pane.focus, focusVar == nil {
                    focusVar = paneVar
                }
            case .split(let split):
                let secondVar = nextVar()
                let flag = split.direction == .columns ? "--right" : "--bottom"
                let secondPercent = max(15, min(85, Int(((1.0 - SplitSpec.clampedRatio(split.ratio)) * 100.0).rounded())))
                let secondCwd = CommandFormatter.expandTilde(
                    layout.effectiveWorkingDirectory(for: split.second.firstLeaf),
                    homeDirectory: context.homeDirectory
                )
                lines.append("\(secondVar)=\"$(\"$WEZTERM_BIN\" cli split-pane --pane-id \"$\(paneVar)\" \(flag) --percent \(secondPercent) --cwd \(CommandFormatter.shellSingleQuote(secondCwd)))\"")
                emitNode(split.first, paneVar: paneVar)
                emitNode(split.second, paneVar: secondVar)
            }
        }

        for (index, tab) in layout.tabs.enumerated() {
            let rootVar = nextVar()
            let firstCwd = CommandFormatter.expandTilde(
                layout.effectiveWorkingDirectory(for: tab.root.firstLeaf),
                homeDirectory: context.homeDirectory
            )
            if index == 0 {
                lines.append("\(rootVar)=\"$(\"$WEZTERM_BIN\" cli spawn --new-window --cwd \(CommandFormatter.shellSingleQuote(firstCwd)))\"")
            } else {
                lines.append("\(rootVar)=\"$(\"$WEZTERM_BIN\" cli spawn --pane-id \"$PANE_0\" --cwd \(CommandFormatter.shellSingleQuote(firstCwd)))\"")
            }
            lines.append("\"$WEZTERM_BIN\" cli set-tab-title --pane-id \"$\(rootVar)\" \(CommandFormatter.shellSingleQuote(tab.title))")
            emitNode(tab.root, paneVar: rootVar)
        }

        if let focusVar {
            lines.append("\"$WEZTERM_BIN\" cli activate-pane --pane-id \"$\(focusVar)\"")
        }

        let script = lines.joined(separator: "\n") + "\n"

        return LaunchPlan(
            terminal: .wezterm,
            layoutName: layout.name,
            summary: "Orchestrates \(layout.tabs.count) tab(s) and \(layout.totalPaneCount) split pane(s) via wezterm cli.",
            previewTitle: "WezTerm CLI Script",
            previewLanguage: "zsh",
            previewContent: script,
            action: .shellScript(script)
        )
    }

    // MARK: - 5. Kitty (Native Kitty Session File with layout splits)

    private static func buildKittyPlan(layout: TesseraLayout, context: LaunchContext) -> LaunchPlan {
        let sessionDir = "\(context.homeDirectory)/.cache/tessera/sessions"
        let sessionPath = "\(sessionDir)/tessera_\(layout.slug).kitty"

        var lines: [String] = []
        lines.append("# Generated by Tessera — \(layout.name)")

        func emitKittyLeaf(
            _ pane: PaneSpec,
            location: String?,
            biasPercent: Int?
        ) {
            let cwd = CommandFormatter.expandTilde(
                layout.effectiveWorkingDirectory(for: pane),
                homeDirectory: context.homeDirectory
            )
            lines.append("cd \(cwd)")
            for entry in pane.environment where CommandFormatter.isValidEnvKey(entry.key) {
                lines.append("env \(entry.key)=\(entry.value)")
            }

            var launchArgs: [String] = ["launch"]
            if !pane.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                launchArgs.append("--title \(CommandFormatter.shellSingleQuote(pane.title))")
            }
            if let location {
                launchArgs.append("--location=\(location)")
            }
            if let biasPercent {
                launchArgs.append("--bias=\(biasPercent)")
            }

            let cmd = CommandFormatter.buildPaneCommandLine(pane: pane, workingDirectory: cwd, includeCD: false)
            if !cmd.isEmpty {
                let payload = CommandFormatter.interactiveShellPayload(command: cmd)
                launchArgs.append("/bin/zsh -lc \(CommandFormatter.shellSingleQuote(payload))")
            }
            lines.append(launchArgs.joined(separator: " "))
            if pane.focus {
                lines.append("focus")
            }
        }

        func emitKittyNode(_ node: PaneNode, pendingLocation: String?, pendingBias: Int?) {
            switch node {
            case .leaf(let pane):
                emitKittyLeaf(pane, location: pendingLocation, biasPercent: pendingBias)
            case .split(let split):
                let splitLoc = split.direction == .columns ? "vsplit" : "hsplit"
                let secondBias = max(15, min(85, Int(((1.0 - SplitSpec.clampedRatio(split.ratio)) * 100.0).rounded())))
                emitKittyNode(split.first, pendingLocation: pendingLocation, pendingBias: pendingBias)
                emitKittyNode(split.second, pendingLocation: splitLoc, pendingBias: secondBias)
            }
        }

        for tab in layout.tabs {
            lines.append("new_tab \(tab.title)")
            lines.append("layout splits")
            emitKittyNode(tab.root, pendingLocation: nil, pendingBias: nil)
        }

        let sessionContent = lines.joined(separator: "\n") + "\n"
        let shellCommand = """
        KITTY_BIN="$(command -v kitty || echo '/Applications/kitty.app/Contents/MacOS/kitty')"
        if [[ -x "$KITTY_BIN" ]]; then
            "$KITTY_BIN" --session \(CommandFormatter.shellSingleQuote(sessionPath)) >/dev/null 2>&1 &
        else
            open -na kitty --args --session \(CommandFormatter.shellSingleQuote(sessionPath))
        fi
        """

        return LaunchPlan(
            terminal: .kitty,
            layoutName: layout.name,
            summary: "Generates a native Kitty split session file and launches Kitty.",
            previewTitle: "Kitty Session (\(layout.slug).kitty)",
            previewLanguage: "conf",
            previewContent: sessionContent,
            action: .writeFileAndRunShell(
                filePath: sessionPath,
                fileContent: sessionContent,
                shellCommand: shellCommand
            )
        )
    }

    // MARK: - 6. Ghostty (GPU-Accelerated CLI Launch + Geometry)

    private static func buildGhosttyPlan(layout: TesseraLayout, context: LaunchContext) -> LaunchPlan {
        let containerRect = layout.windowFrame.resolveRect(screen: context.screenBounds)
            ?? WindowFramePreset.centeredLarge.resolveRect(screen: context.screenBounds)
            ?? context.screenBounds

        var lines: [String] = []
        lines.append("#!/bin/zsh")
        lines.append("set -euo pipefail")
        lines.append("# Tessera Mosaic for Ghostty: \(layout.name)")

        for tab in layout.tabs {
            let frames = LayoutGeometry.computeFrames(root: tab.root, in: containerRect, gap: 10)
            for frame in frames {
                let pane = frame.pane
                let cwd = CommandFormatter.expandTilde(
                    layout.effectiveWorkingDirectory(for: pane),
                    homeDirectory: context.homeDirectory
                )
                let cmd = CommandFormatter.buildPaneCommandLine(pane: pane, workingDirectory: cwd, includeCD: false)
                let payload = CommandFormatter.interactiveShellPayload(command: cmd)
                let cols = max(40, Int((frame.rect.width / 8.5).rounded()))
                let rows = max(14, Int((frame.rect.height / 18.0).rounded()))
                let title = layout.tabs.count > 1 ? "\(tab.title) · \(pane.title)" : pane.title

                lines.append(
                    "open -na Ghostty --args " +
                    "--working-directory=\(CommandFormatter.shellSingleQuote(cwd)) " +
                    "--title=\(CommandFormatter.shellSingleQuote(title)) " +
                    "--window-width=\(cols) " +
                    "--window-height=\(rows) " +
                    "-e /bin/zsh -lc \(CommandFormatter.shellSingleQuote(payload))"
                )
            }
        }

        let script = lines.joined(separator: "\n") + "\n"
        var warnings: [String] = []
        if layout.totalPaneCount > 1 {
            warnings.append("Ghostty does not yet expose an external split-pane IPC API; Tessera launches each pane as a sized Ghostty window (or use tmux inside Ghostty for single-window splits).")
        }

        return LaunchPlan(
            terminal: .ghostty,
            layoutName: layout.name,
            summary: "Launches \(layout.totalPaneCount) Ghostty window(s) sized to your layout proportions.",
            warnings: warnings,
            previewTitle: "Ghostty Launch Script",
            previewLanguage: "zsh",
            previewContent: script,
            action: .shellScript(script)
        )
    }

    // MARK: - 7. Alacritty (Geometric Multi-Window Tiling)

    private static func buildAlacrittyPlan(layout: TesseraLayout, context: LaunchContext) -> LaunchPlan {
        let containerRect = layout.windowFrame.resolveRect(screen: context.screenBounds)
            ?? WindowFramePreset.centeredLarge.resolveRect(screen: context.screenBounds)
            ?? context.screenBounds

        var lines: [String] = []
        lines.append("#!/bin/zsh")
        lines.append("set -euo pipefail")
        lines.append("# Tessera Mosaic for Alacritty: \(layout.name)")
        lines.append("ALACRITTY_BIN=\"$(command -v alacritty || echo '/Applications/Alacritty.app/Contents/MacOS/alacritty')\"")
        lines.append("if [[ ! -x \"$ALACRITTY_BIN\" ]]; then echo 'Alacritty binary not found' >&2; exit 1; fi")

        for tab in layout.tabs {
            let frames = LayoutGeometry.computeFrames(root: tab.root, in: containerRect, gap: 10)
            for frame in frames {
                let pane = frame.pane
                let cwd = CommandFormatter.expandTilde(
                    layout.effectiveWorkingDirectory(for: pane),
                    homeDirectory: context.homeDirectory
                )
                let cmd = CommandFormatter.buildPaneCommandLine(pane: pane, workingDirectory: cwd, includeCD: false)
                let payload = CommandFormatter.interactiveShellPayload(command: cmd)
                let posX = Int(frame.rect.x.rounded())
                let posY = Int(frame.rect.y.rounded())
                let cols = max(40, Int((frame.rect.width / 8.5).rounded()))
                let rows = max(14, Int((frame.rect.height / 18.0).rounded()))
                let title = layout.tabs.count > 1 ? "\(tab.title) · \(pane.title)" : pane.title

                lines.append(
                    "\"$ALACRITTY_BIN\" " +
                    "--working-directory \(CommandFormatter.shellSingleQuote(cwd)) " +
                    "--title \(CommandFormatter.shellSingleQuote(title)) " +
                    "-o \"window.position.x=\(posX)\" " +
                    "-o \"window.position.y=\(posY)\" " +
                    "-o \"window.dimensions.columns=\(cols)\" " +
                    "-o \"window.dimensions.lines=\(rows)\" " +
                    "-e /bin/zsh -lc \(CommandFormatter.shellSingleQuote(payload)) >/dev/null 2>&1 &"
                )
            }
        }

        let script = lines.joined(separator: "\n") + "\n"
        var warnings: [String] = []
        if layout.totalPaneCount > 1 {
            warnings.append("Alacritty relies on window managers for splits; Tessera positions each Alacritty window geometrically across your screen.")
        }

        return LaunchPlan(
            terminal: .alacritty,
            layoutName: layout.name,
            summary: "Launches \(layout.totalPaneCount) geometrically positioned Alacritty window(s).",
            warnings: warnings,
            previewTitle: "Alacritty Tiling Script",
            previewLanguage: "zsh",
            previewContent: script,
            action: .shellScript(script)
        )
    }

    // MARK: - 8. tmux (Exact Split Percentages + Automatic Host Terminal Attach)

    private static func buildTmuxPlan(layout: TesseraLayout, context: LaunchContext) -> LaunchPlan {
        var lines: [String] = []
        lines.append("#!/bin/zsh")
        lines.append("set -euo pipefail")
        lines.append("# Tessera Mosaic via tmux: \(layout.name)")
        lines.append("TMUX_BIN=\"$(command -v tmux || echo '/opt/homebrew/bin/tmux')\"")
        lines.append("if [[ ! -x \"$TMUX_BIN\" ]]; then echo 'tmux not found in PATH' >&2; exit 1; fi")
        lines.append("BASE_SESSION=\(CommandFormatter.shellSingleQuote("tessera-\(layout.slug)"))")
        lines.append("SESSION=\"$BASE_SESSION\"")
        lines.append("if \"$TMUX_BIN\" has-session -t \"$SESSION\" 2>/dev/null; then SESSION=\"${BASE_SESSION}-$(date +%H%M%S)\"; fi")

        var paneCounter = 0
        func nextVar() -> String {
            defer { paneCounter += 1 }
            return "PANE_\(paneCounter)"
        }

        var focusPaneVar: String?
        var focusWindowIndex: Int?

        func emitNode(_ node: PaneNode, paneVar: String, windowIdx: Int) {
            switch node {
            case .leaf(let pane):
                let cwd = layout.effectiveWorkingDirectory(for: pane)
                let cmd = CommandFormatter.buildPaneCommandLine(pane: pane, workingDirectory: cwd, includeCD: false)
                if !pane.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    lines.append("\"$TMUX_BIN\" select-pane -t \"$\(paneVar)\" -T \(CommandFormatter.shellSingleQuote(pane.title))")
                }
                if !cmd.isEmpty {
                    lines.append("\"$TMUX_BIN\" send-keys -t \"$\(paneVar)\" -l \(CommandFormatter.shellSingleQuote(cmd))")
                    lines.append("\"$TMUX_BIN\" send-keys -t \"$\(paneVar)\" Enter")
                }
                if pane.focus, focusPaneVar == nil {
                    focusPaneVar = paneVar
                    focusWindowIndex = windowIdx
                }
            case .split(let split):
                let secondVar = nextVar()
                let flag = split.direction == .columns ? "-h" : "-v"
                let secondPercent = max(15, min(85, Int(((1.0 - SplitSpec.clampedRatio(split.ratio)) * 100.0).rounded())))
                let secondCwd = CommandFormatter.expandTilde(
                    layout.effectiveWorkingDirectory(for: split.second.firstLeaf),
                    homeDirectory: context.homeDirectory
                )
                lines.append("\(secondVar)=\"$(\"$TMUX_BIN\" split-window \(flag) -l \(secondPercent)% -t \"$\(paneVar)\" -c \(CommandFormatter.shellSingleQuote(secondCwd)) -P -F '#{pane_id}')\"")
                emitNode(split.first, paneVar: paneVar, windowIdx: windowIdx)
                emitNode(split.second, paneVar: secondVar, windowIdx: windowIdx)
            }
        }

        for (index, tab) in layout.tabs.enumerated() {
            let rootVar = nextVar()
            let firstCwd = CommandFormatter.expandTilde(
                layout.effectiveWorkingDirectory(for: tab.root.firstLeaf),
                homeDirectory: context.homeDirectory
            )
            if index == 0 {
                lines.append("\(rootVar)=\"$(\"$TMUX_BIN\" new-session -d -s \"$SESSION\" -n \(CommandFormatter.shellSingleQuote(tab.title)) -c \(CommandFormatter.shellSingleQuote(firstCwd)) -P -F '#{pane_id}')\"")
            } else {
                lines.append("\(rootVar)=\"$(\"$TMUX_BIN\" new-window -t \"$SESSION\" -n \(CommandFormatter.shellSingleQuote(tab.title)) -c \(CommandFormatter.shellSingleQuote(firstCwd)) -P -F '#{pane_id}')\"")
            }
            emitNode(tab.root, paneVar: rootVar, windowIdx: index)
        }

        if let focusWindowIndex {
            lines.append("\"$TMUX_BIN\" select-window -t \"$SESSION:\(focusWindowIndex)\" 2>/dev/null || true")
        }
        if let focusPaneVar {
            lines.append("\"$TMUX_BIN\" select-pane -t \"$\(focusPaneVar)\"")
        }

        // Attach inside iTerm2 or Apple Terminal automatically
        if context.hostTerminalForTmux == .iterm2 {
            lines.append("""
            osascript <<EOF
            tell application id "com.googlecode.iterm2"
                activate
                set newWin to (create window with default profile)
                tell current session of newWin
                    write text "\\"$TMUX_BIN\\" attach-session -t \\"$SESSION\\""
                end tell
            end tell
            EOF
            """)
        } else {
            lines.append("""
            osascript <<EOF
            tell application id "com.apple.Terminal"
                activate
                do script "\\"$TMUX_BIN\\" attach-session -t \\"$SESSION\\""
            end tell
            EOF
            """)
        }

        let script = lines.joined(separator: "\n") + "\n"

        return LaunchPlan(
            terminal: .tmux,
            layoutName: layout.name,
            summary: "Creates a tmux session with \(layout.tabs.count) window(s) and \(layout.totalPaneCount) pane(s), then attaches.",
            previewTitle: "tmux Orchestration Script",
            previewLanguage: "zsh",
            previewContent: script,
            action: .shellScript(script)
        )
    }
}
