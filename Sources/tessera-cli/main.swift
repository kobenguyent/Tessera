import Foundation
import TesseraCore

@main
struct TesseraCLI {
    static func main() async {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            return
        }

        switch command.lowercased() {
        case "list", "ls":
            runList()
        case "run", "launch", "open":
            await runLaunch(args: Array(args.dropFirst()))
        case "terminals", "drivers":
            runTerminals()
        case "check-update", "update":
            await runCheckUpdate(args: Array(args.dropFirst()))
        case "export":
            runExport(args: Array(args.dropFirst()))
        case "import":
            runImport(args: Array(args.dropFirst()))
        case "version", "-v", "--version":
            print("tessera \(TesseraMetadata.currentVersionString)")
        case "help", "-h", "--help":
            printUsage()
        default:
            fputs("Unknown command: \(command)\n\n", stderr)
            printUsage()
            exit(1)
        }
    }

    private static func printUsage() {
        print("""
        ✦ Tessera — Craft bespoke terminal mosaics & command rituals (v\(TesseraMetadata.currentVersionString))

        USAGE:
          tessera list                                  List all configured mosaic layouts
          tessera run <layout> [options]                Launch a layout by name or slug
            --terminal, -t <name>                       Override terminal (iterm2, terminal, warp, wezterm, kitty, ghostty, alacritty, tmux)
            --cwd <path>                                Override root working directory
            --dry-run                                   Print the generated orchestration script without executing
          tessera terminals                             Show detected terminal emulators and capabilities
          tessera check-update [--repo owner/repo]      Check GitHub Releases for a newer version
            --prerelease                                Include pre-release builds
          tessera export <file.json>                    Export all layouts to JSON
          tessera import <file.json>                    Import layouts from JSON
          tessera version                               Print version
        """)
    }

    private static func runList() {
        let store = LayoutStore()
        do {
            let layouts = try store.loadLayouts()
            if layouts.isEmpty {
                print("No layouts configured.")
                return
            }
            print("Configured Tessera Layouts (\(layouts.count)):")
            for layout in layouts {
                let pin = layout.isPinned ? "★" : " "
                let terminal = layout.preferredTerminal?.displayName ?? "Default"
                print("  \(pin) \(layout.name) [\(layout.slug)] — \(layout.tabs.count) tab(s), \(layout.totalPaneCount) pane(s) · \(terminal)")
            }
        } catch {
            fputs("Error loading layouts: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runLaunch(args: [String]) async {
        guard !args.isEmpty else {
            fputs("Usage: tessera run <layout-name-or-slug> [--terminal <kind>] [--cwd <dir>] [--dry-run]\n", stderr)
            exit(1)
        }

        var targetQuery: String?
        var terminalOverride: TerminalKind?
        var cwdOverride: String?
        var dryRun = false

        var idx = 0
        while idx < args.count {
            let arg = args[idx]
            switch arg {
            case "--terminal", "-t":
                idx += 1
                guard idx < args.count, let parsed = TerminalKind.fromCLIArgument(args[idx]) else {
                    fputs("Invalid terminal name. Supported: \(TerminalKind.allCases.map(\.rawValue).joined(separator: ", "))\n", stderr)
                    exit(1)
                }
                terminalOverride = parsed
            case "--cwd":
                idx += 1
                guard idx < args.count else {
                    fputs("Missing value for --cwd\n", stderr)
                    exit(1)
                }
                cwdOverride = args[idx]
            case "--dry-run":
                dryRun = true
            default:
                if targetQuery == nil {
                    targetQuery = arg
                }
            }
            idx += 1
        }

        guard let query = targetQuery else {
            fputs("Please specify a layout name or slug.\n", stderr)
            exit(1)
        }

        let store = LayoutStore()
        let settings = SettingsStore().load()
        let detector = TerminalDetector()

        do {
            let layouts = try store.loadLayouts()
            let lowerQuery = query.lowercased()
            guard var layout = layouts.first(where: {
                $0.slug == lowerQuery || $0.name.lowercased() == lowerQuery
            }) ?? layouts.first(where: {
                $0.name.lowercased().contains(lowerQuery) || $0.slug.contains(lowerQuery)
            }) else {
                fputs("Layout \"\(query)\" not found. Run `tessera list` to see available layouts.\n", stderr)
                exit(1)
            }

            if let cwdOverride {
                layout.workingDirectory = cwdOverride
            }

            let terminal = terminalOverride ?? layout.preferredTerminal ?? settings.defaultTerminal
            let hostForTmux: TerminalKind = detector.detect(.iterm2).isInstalled ? .iterm2 : .appleTerminal
            let context = LaunchContext(hostTerminalForTmux: hostForTmux)
            let plan = LaunchPlanBuilder.build(layout: layout, terminal: terminal, context: context)

            if dryRun {
                print("# \(plan.previewTitle)")
                print("# \(plan.summary)")
                for warning in plan.warnings {
                    print("# Note: \(warning)")
                }
                print("")
                print(plan.previewContent)
                return
            }

            for warning in plan.warnings {
                fputs("Note: \(warning)\n", stderr)
            }

            let launcher = TerminalLauncher()
            let result = await launcher.execute(plan)
            if result.succeeded {
                print("✓ \(result.message)")
            } else {
                fputs("✗ \(result.message)\n", stderr)
                exit(1)
            }
        } catch {
            fputs("Failed to launch layout: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runTerminals() {
        let detected = TerminalDetector().detectAll()
        print("Supported Terminal Drivers:")
        for item in detected {
            let status = item.isInstalled ? "✓ Installed" : "· Not found"
            let caps = item.kind.capabilities
            let splits = caps.nativeSplits ? "Native Splits" : "Tiled Windows"
            let pathNote = item.resolvedPath.map { " (\($0))" } ?? ""
            print("  \(status.padding(toLength: 12, withPad: " ", startingAt: 0)) \(item.kind.displayName.padding(toLength: 16, withPad: " ", startingAt: 0)) [\(splits)]\(pathNote)")
        }
    }

    private static func runCheckUpdate(args: [String]) async {
        let settings = SettingsStore().load()
        var repo = settings.githubRepository
        var includePrereleases = settings.includePrereleases

        var idx = 0
        while idx < args.count {
            switch args[idx] {
            case "--repo":
                idx += 1
                if idx < args.count { repo = args[idx] }
            case "--prerelease":
                includePrereleases = true
            default:
                break
            }
            idx += 1
        }

        let current = TesseraMetadata.currentVersion
        print("Checking GitHub Releases for \(repo) (current: v\(current))...")
        let service = UpdateService()
        do {
            let outcome = try await service.checkForUpdates(
                repository: repo,
                currentVersion: current,
                includePrereleases: includePrereleases,
                ignoreSkipped: true
            )
            switch outcome {
            case .upToDate(_, let latest):
                if let latest {
                    print("✓ Tessera is up to date (latest: v\(latest)).")
                } else {
                    print("✓ No newer releases found.")
                }
            case .updateAvailable(let update), .skipped(let update):
                print("✦ Update available: \(update.release.displayTitle) (v\(update.version))")
                if let asset = update.preferredAsset {
                    print("  Asset: \(asset.name) (\(asset.formattedSize))")
                    print("  Download: \(asset.browserDownloadURL.absoluteString)")
                }
                print("  Release page: \(update.release.htmlURL.absoluteString)")
            }
        } catch {
            fputs("Update check failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runExport(args: [String]) {
        guard let path = args.first else {
            fputs("Usage: tessera export <output.json>\n", stderr)
            exit(1)
        }
        let store = LayoutStore()
        do {
            let layouts = try store.loadLayouts()
            let data = try store.exportJSON(layouts: layouts)
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            print("✓ Exported \(layouts.count) layout(s) to \(path)")
        } catch {
            fputs("Export failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }

    private static func runImport(args: [String]) {
        guard let path = args.first else {
            fputs("Usage: tessera import <input.json>\n", stderr)
            exit(1)
        }
        let store = LayoutStore()
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: path))
            let imported = try store.importJSON(from: data)
            var existing = (try? store.loadLayouts()) ?? []
            for item in imported {
                if let existingIdx = existing.firstIndex(where: { $0.id == item.id }) {
                    existing[existingIdx] = item
                } else {
                    existing.append(item)
                }
            }
            try store.saveLayouts(existing)
            print("✓ Imported \(imported.count) layout(s). Total layouts: \(existing.count)")
        } catch {
            fputs("Import failed: \(error.localizedDescription)\n", stderr)
            exit(1)
        }
    }
}
