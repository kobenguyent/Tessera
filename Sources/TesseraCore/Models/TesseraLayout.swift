import Foundation

public struct TesseraRect: Codable, Equatable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
}

public enum WindowFramePreset: String, Codable, CaseIterable, Hashable, Sendable {
    case `default`
    case maximized
    case centeredLarge
    case leftHalf
    case rightHalf

    public var displayName: String {
        switch self {
        case .default: return "Terminal Default"
        case .maximized: return "Fill Screen"
        case .centeredLarge: return "Centered Studio (82%)"
        case .leftHalf: return "Left Half"
        case .rightHalf: return "Right Half"
        }
    }

    public var symbolName: String {
        switch self {
        case .default: return "macwindow"
        case .maximized: return "arrow.up.left.and.arrow.down.right"
        case .centeredLarge: return "rectangle.center.inset.filled"
        case .leftHalf: return "rectangle.lefthalf.filled"
        case .rightHalf: return "rectangle.righthalf.filled"
        }
    }

    /// Computes a concrete pixel rectangle (top-left origin, AppleScript / macOS window bounds style)
    /// given the visible screen work area.
    public func resolveRect(screen: TesseraRect) -> TesseraRect? {
        switch self {
        case .default:
            return nil
        case .maximized:
            let inset = 12.0
            return TesseraRect(
                x: screen.x + inset,
                y: screen.y + inset,
                width: max(400, screen.width - inset * 2),
                height: max(300, screen.height - inset * 2)
            )
        case .centeredLarge:
            let width = max(640, screen.width * 0.82)
            let height = max(460, screen.height * 0.82)
            return TesseraRect(
                x: screen.x + (screen.width - width) / 2.0,
                y: screen.y + (screen.height - height) / 2.0,
                width: width,
                height: height
            )
        case .leftHalf:
            let gap = 10.0
            return TesseraRect(
                x: screen.x + gap,
                y: screen.y + gap,
                width: max(360, screen.width / 2.0 - gap * 1.5),
                height: max(300, screen.height - gap * 2)
            )
        case .rightHalf:
            let gap = 10.0
            let width = max(360, screen.width / 2.0 - gap * 1.5)
            return TesseraRect(
                x: screen.x + screen.width / 2.0 + gap * 0.5,
                y: screen.y + gap,
                width: width,
                height: max(300, screen.height - gap * 2)
            )
        }
    }
}

public struct TesseraTab: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var root: PaneNode

    public init(id: UUID = UUID(), title: String = "Workspace", root: PaneNode) {
        self.id = id
        self.title = title
        self.root = root
    }

    public func clonedWithFreshIDs() -> TesseraTab {
        TesseraTab(id: UUID(), title: title, root: root.clonedWithFreshIDs())
    }
}

public struct TesseraLayout: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var name: String
    public var subtitle: String
    public var icon: String
    public var accentHex: String
    public var preferredTerminal: TerminalKind?
    public var workingDirectory: String
    public var windowFrame: WindowFramePreset
    public var tabs: [TesseraTab]
    public var tags: [String]
    public var isPinned: Bool
    public var isBuiltIn: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        subtitle: String = "",
        icon: String = "square.grid.2x2",
        accentHex: String = "#6366F1",
        preferredTerminal: TerminalKind? = nil,
        workingDirectory: String = "~",
        windowFrame: WindowFramePreset = .centeredLarge,
        tabs: [TesseraTab],
        tags: [String] = [],
        isPinned: Bool = false,
        isBuiltIn: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.subtitle = subtitle
        self.icon = icon
        self.accentHex = accentHex
        self.preferredTerminal = preferredTerminal
        self.workingDirectory = workingDirectory
        self.windowFrame = windowFrame
        self.tabs = tabs.isEmpty ? [TesseraTab(root: .leaf(PaneSpec()))] : tabs
        self.tags = tags
        self.isPinned = isPinned
        self.isBuiltIn = isBuiltIn
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    public var totalPaneCount: Int {
        tabs.reduce(0) { $0 + $1.root.leafCount }
    }

    public var slug: String {
        let lower = name.lowercased()
        let mapped = lower.map { char -> Character in
            (char.isLetter || char.isNumber) ? char : "-"
        }
        let collapsed = String(mapped)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return collapsed.isEmpty ? "tessera-layout" : collapsed
    }

    public func effectiveWorkingDirectory(for pane: PaneSpec) -> String {
        if let override = pane.workingDirectory?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return override
        }
        let layoutDir = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return layoutDir.isEmpty ? "~" : layoutDir
    }

    public func duplicated(newName: String? = nil) -> TesseraLayout {
        let now = Date()
        return TesseraLayout(
            id: UUID(),
            name: newName ?? "\(name) Copy",
            subtitle: subtitle,
            icon: icon,
            accentHex: accentHex,
            preferredTerminal: preferredTerminal,
            workingDirectory: workingDirectory,
            windowFrame: windowFrame,
            tabs: tabs.map { $0.clonedWithFreshIDs() },
            tags: tags,
            isPinned: false,
            isBuiltIn: false,
            createdAt: now,
            updatedAt: now
        )
    }
}

public struct PaneFrame: Identifiable, Equatable, Sendable {
    public var id: UUID { pane.id }
    public let pane: PaneSpec
    public let rect: TesseraRect

    public init(pane: PaneSpec, rect: TesseraRect) {
        self.pane = pane
        self.rect = rect
    }
}

/// Computes exact geometric layout frames for any `PaneNode` inside a container rect.
/// Used both by the SwiftUI Mosaic Canvas preview and by tiled-window terminal adapters
/// (Apple Terminal, Alacritty).
public enum LayoutGeometry {
    public static func computeFrames(
        root: PaneNode,
        in bounds: TesseraRect,
        gap: Double = 0
    ) -> [PaneFrame] {
        switch root {
        case .leaf(let pane):
            return [PaneFrame(pane: pane, rect: bounds)]
        case .split(let split):
            let ratio = SplitSpec.clampedRatio(split.ratio)
            switch split.direction {
            case .columns:
                let availableWidth = max(0, bounds.width - gap)
                let firstWidth = availableWidth * ratio
                let secondWidth = availableWidth - firstWidth
                let firstRect = TesseraRect(
                    x: bounds.x,
                    y: bounds.y,
                    width: firstWidth,
                    height: bounds.height
                )
                let secondRect = TesseraRect(
                    x: bounds.x + firstWidth + gap,
                    y: bounds.y,
                    width: secondWidth,
                    height: bounds.height
                )
                return computeFrames(root: split.first, in: firstRect, gap: gap)
                    + computeFrames(root: split.second, in: secondRect, gap: gap)
            case .rows:
                let availableHeight = max(0, bounds.height - gap)
                let firstHeight = availableHeight * ratio
                let secondHeight = availableHeight - firstHeight
                let firstRect = TesseraRect(
                    x: bounds.x,
                    y: bounds.y,
                    width: bounds.width,
                    height: firstHeight
                )
                let secondRect = TesseraRect(
                    x: bounds.x,
                    y: bounds.y + firstHeight + gap,
                    width: bounds.width,
                    height: secondHeight
                )
                return computeFrames(root: split.first, in: firstRect, gap: gap)
                    + computeFrames(root: split.second, in: secondRect, gap: gap)
            }
        }
    }
}
