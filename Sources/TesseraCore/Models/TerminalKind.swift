import Foundation

public struct TerminalCapabilities: Equatable, Hashable, Sendable {
    public let nativeSplits: Bool
    public let nativeTabs: Bool
    public let supportsProfiles: Bool
    public let supportsWindowBounds: Bool
    public let orchestrationMethod: String

    public init(
        nativeSplits: Bool,
        nativeTabs: Bool,
        supportsProfiles: Bool,
        supportsWindowBounds: Bool,
        orchestrationMethod: String
    ) {
        self.nativeSplits = nativeSplits
        self.nativeTabs = nativeTabs
        self.supportsProfiles = supportsProfiles
        self.supportsWindowBounds = supportsWindowBounds
        self.orchestrationMethod = orchestrationMethod
    }
}

public enum TerminalKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case iterm2
    case appleTerminal
    case warp
    case wezterm
    case kitty
    case ghostty
    case alacritty
    case tmux

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .iterm2: return "iTerm2"
        case .appleTerminal: return "Apple Terminal"
        case .warp: return "Warp"
        case .wezterm: return "WezTerm"
        case .kitty: return "Kitty"
        case .ghostty: return "Ghostty"
        case .alacritty: return "Alacritty"
        case .tmux: return "tmux"
        }
    }

    public var shortSummary: String {
        switch self {
        case .iterm2: return "Full native splits, tabs, profiles & window bounds via AppleScript"
        case .appleTerminal: return "Built-in macOS Terminal with geometric tiled mosaic windows"
        case .warp: return "Native splits & tabs via Warp Launch Configuration YAML"
        case .wezterm: return "Native splits with exact percentages & tabs via wezterm cli"
        case .kitty: return "Native split layouts & tabs via Kitty session files"
        case .ghostty: return "GPU-accelerated terminal via Ghostty CLI & native window splits"
        case .alacritty: return "Fast GPU terminal with geometric multi-window tiling"
        case .tmux: return "Universal tmux session with exact split percentages attached in a terminal"
        }
    }

    public var symbolName: String {
        switch self {
        case .iterm2: return "terminal.fill"
        case .appleTerminal: return "apple.terminal"
        case .warp: return "bolt.horizontal.circle.fill"
        case .wezterm: return "rectangle.split.3x3"
        case .kitty: return "cat.fill"
        case .ghostty: return "terminal.fill"
        case .alacritty: return "flame.fill"
        case .tmux: return "square.split.2x2.fill"
        }
    }

    public var bundleIdentifier: String? {
        switch self {
        case .iterm2: return "com.googlecode.iterm2"
        case .appleTerminal: return "com.apple.Terminal"
        case .warp: return "dev.warp.Warp-Stable"
        case .wezterm: return "com.github.wez.wezterm"
        case .kitty: return "net.kovidgoyal.kitty"
        case .ghostty: return "com.mitchellh.ghostty"
        case .alacritty: return "org.alacritty"
        case .tmux: return nil
        }
    }

    public var appNames: [String] {
        switch self {
        case .iterm2: return ["iTerm.app", "iTerm2.app"]
        case .appleTerminal: return ["Terminal.app"]
        case .warp: return ["Warp.app"]
        case .wezterm: return ["WezTerm.app"]
        case .kitty: return ["kitty.app", "Kitty.app"]
        case .ghostty: return ["Ghostty.app"]
        case .alacritty: return ["Alacritty.app"]
        case .tmux: return []
        }
    }

    public var cliExecutableNames: [String] {
        switch self {
        case .iterm2, .appleTerminal, .warp: return []
        case .wezterm: return ["wezterm"]
        case .kitty: return ["kitty"]
        case .ghostty: return ["ghostty"]
        case .alacritty: return ["alacritty"]
        case .tmux: return ["tmux"]
        }
    }

    public var capabilities: TerminalCapabilities {
        switch self {
        case .iterm2:
            return TerminalCapabilities(
                nativeSplits: true,
                nativeTabs: true,
                supportsProfiles: true,
                supportsWindowBounds: true,
                orchestrationMethod: "AppleScript (iTerm2 Dictionary)"
            )
        case .appleTerminal:
            return TerminalCapabilities(
                nativeSplits: false,
                nativeTabs: true,
                supportsProfiles: true,
                supportsWindowBounds: true,
                orchestrationMethod: "AppleScript (Geometric Window Mosaic)"
            )
        case .warp:
            return TerminalCapabilities(
                nativeSplits: true,
                nativeTabs: true,
                supportsProfiles: false,
                supportsWindowBounds: false,
                orchestrationMethod: "Warp Launch Configuration YAML + URI"
            )
        case .wezterm:
            return TerminalCapabilities(
                nativeSplits: true,
                nativeTabs: true,
                supportsProfiles: false,
                supportsWindowBounds: false,
                orchestrationMethod: "wezterm cli"
            )
        case .kitty:
            return TerminalCapabilities(
                nativeSplits: true,
                nativeTabs: true,
                supportsProfiles: false,
                supportsWindowBounds: false,
                orchestrationMethod: "Kitty Session File"
            )
        case .ghostty:
            return TerminalCapabilities(
                nativeSplits: false,
                nativeTabs: false,
                supportsProfiles: false,
                supportsWindowBounds: true,
                orchestrationMethod: "Ghostty CLI (Sized Windows)"
            )
        case .alacritty:
            return TerminalCapabilities(
                nativeSplits: false,
                nativeTabs: false,
                supportsProfiles: false,
                supportsWindowBounds: true,
                orchestrationMethod: "Alacritty CLI (Geometric Window Tiling)"
            )
        case .tmux:
            return TerminalCapabilities(
                nativeSplits: true,
                nativeTabs: true,
                supportsProfiles: false,
                supportsWindowBounds: false,
                orchestrationMethod: "tmux Multiplexer + Host Terminal"
            )
        }
    }

    public static func fromCLIArgument(_ value: String) -> TerminalKind? {
        let normalized = value.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        switch normalized {
        case "iterm", "iterm2": return .iterm2
        case "terminal", "apple", "apple-terminal", "appleterminal": return .appleTerminal
        case "warp": return .warp
        case "wezterm", "wez": return .wezterm
        case "kitty": return .kitty
        case "ghostty": return .ghostty
        case "alacritty": return .alacritty
        case "tmux": return .tmux
        default: return TerminalKind(rawValue: normalized)
        }
    }
}

public struct DetectedTerminal: Identifiable, Equatable, Hashable, Sendable {
    public var id: TerminalKind { kind }
    public let kind: TerminalKind
    public let isInstalled: Bool
    public let resolvedPath: String?

    public init(kind: TerminalKind, isInstalled: Bool, resolvedPath: String?) {
        self.kind = kind
        self.isInstalled = isInstalled
        self.resolvedPath = resolvedPath
    }
}
