import Foundation

/// Quick structural geometry templates users can apply to any tab in 1 click.
public enum MosaicStructureTemplate: String, CaseIterable, Identifiable, Sendable {
    case single
    case sideBySide
    case mainAndStackedSide
    case quadGrid
    case commandCenter
    case threeColumns

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .single: return "Single Focus"
        case .sideBySide: return "Dual Columns"
        case .mainAndStackedSide: return "Main + Side Stack"
        case .quadGrid: return "2×2 Mosaic"
        case .commandCenter: return "1 Top + 3 Bottom"
        case .threeColumns: return "Triple Columns"
        }
    }

    public var symbolName: String {
        switch self {
        case .single: return "rectangle"
        case .sideBySide: return "rectangle.split.2x1"
        case .mainAndStackedSide: return "rectangle.leftthird.inset.filled"
        case .quadGrid: return "square.grid.2x2"
        case .commandCenter: return "rectangle.topthird.inset.filled"
        case .threeColumns: return "rectangle.split.3x1"
        }
    }

    public func makeTree(preserving existingPanes: [PaneSpec] = []) -> PaneNode {
        func pane(_ index: Int, defaultTitle: String, focus: Bool = false) -> PaneSpec {
            if index < existingPanes.count {
                var existing = existingPanes[index]
                existing.focus = focus
                return existing
            }
            return PaneSpec(title: defaultTitle, focus: focus)
        }

        switch self {
        case .single:
            return .leaf(pane(0, defaultTitle: "Primary Shell", focus: true))
        case .sideBySide:
            return .split(SplitSpec(
                direction: .columns,
                ratio: 0.5,
                first: .leaf(pane(0, defaultTitle: "Left Pane", focus: true)),
                second: .leaf(pane(1, defaultTitle: "Right Pane"))
            ))
        case .mainAndStackedSide:
            return .split(SplitSpec(
                direction: .columns,
                ratio: 0.58,
                first: .leaf(pane(0, defaultTitle: "Main Workspace", focus: true)),
                second: .split(SplitSpec(
                    direction: .rows,
                    ratio: 0.5,
                    first: .leaf(pane(1, defaultTitle: "Server / Runner")),
                    second: .leaf(pane(2, defaultTitle: "Logs / Tests"))
                ))
            ))
        case .quadGrid:
            return .split(SplitSpec(
                direction: .rows,
                ratio: 0.5,
                first: .split(SplitSpec(
                    direction: .columns,
                    ratio: 0.5,
                    first: .leaf(pane(0, defaultTitle: "Top Left", focus: true)),
                    second: .leaf(pane(1, defaultTitle: "Top Right"))
                )),
                second: .split(SplitSpec(
                    direction: .columns,
                    ratio: 0.5,
                    first: .leaf(pane(2, defaultTitle: "Bottom Left")),
                    second: .leaf(pane(3, defaultTitle: "Bottom Right"))
                ))
            ))
        case .commandCenter:
            return .split(SplitSpec(
                direction: .rows,
                ratio: 0.45,
                first: .leaf(pane(0, defaultTitle: "Command Deck", focus: true)),
                second: .split(SplitSpec(
                    direction: .columns,
                    ratio: 0.34,
                    first: .leaf(pane(1, defaultTitle: "Stream A")),
                    second: .split(SplitSpec(
                        direction: .columns,
                        ratio: 0.5,
                        first: .leaf(pane(2, defaultTitle: "Stream B")),
                        second: .leaf(pane(3, defaultTitle: "Stream C"))
                    ))
                ))
            ))
        case .threeColumns:
            return .split(SplitSpec(
                direction: .columns,
                ratio: 0.34,
                first: .leaf(pane(0, defaultTitle: "Column 1", focus: true)),
                second: .split(SplitSpec(
                    direction: .columns,
                    ratio: 0.5,
                    first: .leaf(pane(1, defaultTitle: "Column 2")),
                    second: .leaf(pane(2, defaultTitle: "Column 3"))
                ))
            ))
        }
    }
}

/// Curated out-of-the-box mosaic layouts shipped with Tessera.
public enum BuiltInPresets {
    public static func makeDefaultLayouts() -> [TesseraLayout] {
        [
            fullStackFoundry(),
            quadMosaic(),
            threeLaneWorkbench(),
            devOpsCommandDeck(),
            dualFocusPair(),
            multiTabStudio()
        ]
    }

    public static func fullStackFoundry() -> TesseraLayout {
        let root = PaneNode.split(SplitSpec(
            direction: .columns,
            ratio: 0.58,
            first: .leaf(PaneSpec(
                title: "Code & Git",
                commands: ["git status -sb 2>/dev/null || ls -la"],
                focus: true
            )),
            second: .split(SplitSpec(
                direction: .rows,
                ratio: 0.5,
                first: .leaf(PaneSpec(
                    title: "Frontend Dev",
                    commands: ["npm run dev"]
                )),
                second: .leaf(PaneSpec(
                    title: "API & Watcher",
                    commands: ["swift test"],
                    delaySeconds: 0.5
                ))
            ))
        ))

        return TesseraLayout(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000001")!,
            name: "Full-Stack Foundry",
            subtitle: "Primary workspace paired with stacked Frontend and API panes",
            icon: "hammer.fill",
            accentHex: "#6366F1",
            workingDirectory: "~",
            windowFrame: .centeredLarge,
            tabs: [TesseraTab(title: "Foundry", root: root)],
            tags: ["dev", "fullstack", "featured"],
            isPinned: true,
            isBuiltIn: true
        )
    }

    public static func quadMosaic() -> TesseraLayout {
        let root = PaneNode.split(SplitSpec(
            direction: .rows,
            ratio: 0.5,
            first: .split(SplitSpec(
                direction: .columns,
                ratio: 0.5,
                first: .leaf(PaneSpec(
                    title: "App Server",
                    commands: ["pwd && ls -la"],
                    focus: true
                )),
                second: .leaf(PaneSpec(
                    title: "Test Runner",
                    commands: []
                ))
            )),
            second: .split(SplitSpec(
                direction: .columns,
                ratio: 0.5,
                first: .leaf(PaneSpec(
                    title: "System Telemetry",
                    commands: ["uptime && df -h ."]
                )),
                second: .leaf(PaneSpec(
                    title: "Git Workbench",
                    commands: ["git log -n 5 --oneline 2>/dev/null || pwd"]
                ))
            ))
        ))

        return TesseraLayout(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000002")!,
            name: "Quad Mosaic",
            subtitle: "Balanced 2×2 terminal grid for parallel workflows",
            icon: "square.grid.2x2.fill",
            accentHex: "#10B981",
            workingDirectory: "~",
            windowFrame: .maximized,
            tabs: [TesseraTab(title: "Mosaic", root: root)],
            tags: ["grid", "2x2", "featured"],
            isPinned: true,
            isBuiltIn: true
        )
    }

    public static func threeLaneWorkbench() -> TesseraLayout {
        let root = PaneNode.split(SplitSpec(
            direction: .columns,
            ratio: 0.36,
            first: .leaf(PaneSpec(
                title: "Primary Shell",
                commands: ["pwd && ls -la"],
                focus: true
            )),
            second: .split(SplitSpec(
                direction: .columns,
                ratio: 0.5,
                first: .leaf(PaneSpec(
                    title: "Build & Test",
                    commands: []
                )),
                second: .leaf(PaneSpec(
                    title: "Git Diff & Status",
                    commands: ["git status -sb 2>/dev/null || pwd"]
                ))
            ))
        ))

        return TesseraLayout(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000003")!,
            name: "Three-Lane Workbench",
            subtitle: "Three vertical lanes for shell, build verification, and git status",
            icon: "rectangle.split.3x1.fill",
            accentHex: "#A855F7",
            workingDirectory: "~",
            windowFrame: .maximized,
            tabs: [TesseraTab(title: "Workbench", root: root)],
            tags: ["dev", "columns"],
            isPinned: true,
            isBuiltIn: true
        )
    }

    public static func devOpsCommandDeck() -> TesseraLayout {
        let root = PaneNode.split(SplitSpec(
            direction: .rows,
            ratio: 0.45,
            first: .leaf(PaneSpec(
                title: "Cluster Overview",
                commands: ["uname -srm && date"],
                focus: true
            )),
            second: .split(SplitSpec(
                direction: .columns,
                ratio: 0.34,
                first: .leaf(PaneSpec(
                    title: "Containers",
                    commands: ["docker ps"]
                )),
                second: .split(SplitSpec(
                    direction: .columns,
                    ratio: 0.5,
                    first: .leaf(PaneSpec(
                        title: "Live Logs",
                        commands: []
                    )),
                    second: .leaf(PaneSpec(
                        title: "Ops Shell",
                        commands: []
                    ))
                ))
            ))
        ))

        return TesseraLayout(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000004")!,
            name: "DevOps Command Deck",
            subtitle: "Top overview pane above three operational columns",
            icon: "server.rack",
            accentHex: "#F59E0B",
            workingDirectory: "~",
            windowFrame: .maximized,
            tabs: [TesseraTab(title: "Operations", root: root)],
            tags: ["devops", "ops", "monitoring"],
            isPinned: false,
            isBuiltIn: true
        )
    }

    public static func dualFocusPair() -> TesseraLayout {
        let root = PaneNode.split(SplitSpec(
            direction: .columns,
            ratio: 0.5,
            first: .leaf(PaneSpec(
                title: "Primary",
                commands: ["clear && pwd"],
                focus: true
            )),
            second: .leaf(PaneSpec(
                title: "Companion",
                commands: ["clear && ls -la"]
            ))
        ))

        return TesseraLayout(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000005")!,
            name: "Dual Focus Pair",
            subtitle: "Clean 50/50 side-by-side split",
            icon: "rectangle.split.2x1.fill",
            accentHex: "#0EA5E9",
            workingDirectory: "~",
            windowFrame: .centeredLarge,
            tabs: [TesseraTab(title: "Focus", root: root)],
            tags: ["minimal", "pair"],
            isPinned: false,
            isBuiltIn: true
        )
    }

    public static func multiTabStudio() -> TesseraLayout {
        let codeTab = TesseraTab(
            title: "Build",
            root: .split(SplitSpec(
                direction: .columns,
                ratio: 0.55,
                first: .leaf(PaneSpec(
                    title: "Workspace",
                    commands: ["git status -sb 2>/dev/null || ls -la"],
                    focus: true
                )),
                second: .leaf(PaneSpec(
                    title: "Tests",
                    commands: []
                ))
            ))
        )

        let opsTab = TesseraTab(
            title: "Services",
            root: .split(SplitSpec(
                direction: .rows,
                ratio: 0.5,
                first: .leaf(PaneSpec(
                    title: "Database / Cache",
                    commands: []
                )),
                second: .leaf(PaneSpec(
                    title: "API Proxy",
                    commands: []
                ))
            ))
        )

        return TesseraLayout(
            id: UUID(uuidString: "10000000-0000-4000-8000-000000000006")!,
            name: "Multi-Tab Studio",
            subtitle: "Two tabs: Build workspace and Services stack",
            icon: "macwindow.on.rectangle",
            accentHex: "#EC4899",
            workingDirectory: "~",
            windowFrame: .centeredLarge,
            tabs: [codeTab, opsTab],
            tags: ["tabs", "studio"],
            isPinned: false,
            isBuiltIn: true
        )
    }
}
