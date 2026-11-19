import Foundation
#if canImport(AppKit)
import AppKit
#endif

public protocol TerminalDetecting: Sendable {
    func detect(_ kind: TerminalKind) -> DetectedTerminal
    func detectAll() -> [DetectedTerminal]
    func recommendedDefaultTerminal() -> TerminalKind
}

public struct TerminalDetector: TerminalDetecting, Sendable {
    private let extraSearchPaths: [String]

    public init(extraSearchPaths: [String] = []) {
        self.extraSearchPaths = extraSearchPaths
    }

    public func detectAll() -> [DetectedTerminal] {
        TerminalKind.allCases.map { detect($0) }
    }

    public func detect(_ kind: TerminalKind) -> DetectedTerminal {
        if let appPath = resolveApplicationPath(for: kind) {
            return DetectedTerminal(kind: kind, isInstalled: true, resolvedPath: appPath)
        }
        if let cliPath = resolveCLIPath(for: kind) {
            return DetectedTerminal(kind: kind, isInstalled: true, resolvedPath: cliPath)
        }
        return DetectedTerminal(kind: kind, isInstalled: false, resolvedPath: nil)
    }

    public func recommendedDefaultTerminal() -> TerminalKind {
        let priority: [TerminalKind] = [
            .iterm2,
            .ghostty,
            .wezterm,
            .warp,
            .kitty,
            .alacritty,
            .appleTerminal,
            .tmux
        ]
        for candidate in priority {
            if detect(candidate).isInstalled {
                return candidate
            }
        }
        return .appleTerminal
    }

    public func resolveCLIPath(for kind: TerminalKind) -> String? {
        let fm = FileManager.default
        let envPath = ProcessInfo.processInfo.environment["PATH"] ?? ""
        let home = NSHomeDirectory()
        let searchDirs = extraSearchPaths
            + envPath.split(separator: ":").map(String.init)
            + [
                "/opt/homebrew/bin",
                "/usr/local/bin",
                "/usr/bin",
                "\(home)/.local/bin",
                "\(home)/.cargo/bin"
            ]

        // Also check CLI binaries bundled inside .app containers
        let bundledBinaries: [String]
        switch kind {
        case .wezterm:
            bundledBinaries = ["/Applications/WezTerm.app/Contents/MacOS/wezterm"]
        case .kitty:
            bundledBinaries = ["/Applications/kitty.app/Contents/MacOS/kitty"]
        case .ghostty:
            bundledBinaries = ["/Applications/Ghostty.app/Contents/MacOS/ghostty"]
        case .alacritty:
            bundledBinaries = ["/Applications/Alacritty.app/Contents/MacOS/alacritty"]
        default:
            bundledBinaries = []
        }

        for binary in bundledBinaries where fm.isExecutableFile(atPath: binary) {
            return binary
        }

        for exe in kind.cliExecutableNames {
            for dir in searchDirs where !dir.isEmpty {
                let candidate = (dir as NSString).appendingPathComponent(exe)
                if fm.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }
        return nil
    }

    private func resolveApplicationPath(for kind: TerminalKind) -> String? {
        let fm = FileManager.default
        let home = NSHomeDirectory()
        let appDirs = [
            "/Applications",
            "\(home)/Applications",
            "/System/Applications/Utilities",
            "/System/Applications"
        ]

        for appName in kind.appNames {
            for dir in appDirs {
                let fullPath = (dir as NSString).appendingPathComponent(appName)
                if fm.fileExists(atPath: fullPath) {
                    return fullPath
                }
            }
        }

        #if canImport(AppKit)
        if let bundleID = kind.bundleIdentifier,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return url.path
        }
        #endif

        return nil
    }
}
