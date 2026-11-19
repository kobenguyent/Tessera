import Foundation

/// Split orientation using unambiguous spatial semantics.
/// - `columns`: side-by-side panes (left | right, vertical divider line)
/// - `rows`: stacked panes (top / bottom, horizontal divider line)
public enum SplitDirection: String, Codable, CaseIterable, Hashable, Sendable {
    case columns
    case rows

    public var displayName: String {
        switch self {
        case .columns: return "Columns (Left | Right)"
        case .rows: return "Rows (Top / Bottom)"
        }
    }

    public var shortLabel: String {
        switch self {
        case .columns: return "Columns"
        case .rows: return "Rows"
        }
    }

    public var symbolName: String {
        switch self {
        case .columns: return "rectangle.split.2x1"
        case .rows: return "rectangle.split.1x2"
        }
    }
}

public struct EnvEntry: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var key: String
    public var value: String

    public init(id: UUID = UUID(), key: String, value: String) {
        self.id = id
        self.key = key
        self.value = value
    }
}

public struct PaneSpec: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var title: String
    public var workingDirectory: String?
    public var commands: [String]
    public var environment: [EnvEntry]
    public var profile: String?
    public var delaySeconds: Double
    public var focus: Bool

    public init(
        id: UUID = UUID(),
        title: String = "Shell",
        workingDirectory: String? = nil,
        commands: [String] = [],
        environment: [EnvEntry] = [],
        profile: String? = nil,
        delaySeconds: Double = 0,
        focus: Bool = false
    ) {
        self.id = id
        self.title = title
        self.workingDirectory = workingDirectory
        self.commands = commands
        self.environment = environment
        self.profile = profile
        self.delaySeconds = max(0, delaySeconds)
        self.focus = focus
    }

    public var nonEmptyCommands: [String] {
        commands
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

public struct SplitSpec: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var direction: SplitDirection
    /// Fraction allocated to `first`, clamped between 0.15 and 0.85.
    public var ratio: Double
    public var first: PaneNode
    public var second: PaneNode

    public init(
        id: UUID = UUID(),
        direction: SplitDirection,
        ratio: Double = 0.5,
        first: PaneNode,
        second: PaneNode
    ) {
        self.id = id
        self.direction = direction
        self.ratio = SplitSpec.clampedRatio(ratio)
        self.first = first
        self.second = second
    }

    public static func clampedRatio(_ value: Double) -> Double {
        min(0.85, max(0.15, value))
    }
}

/// Recursive binary split-pane layout tree.
public indirect enum PaneNode: Identifiable, Codable, Equatable, Hashable, Sendable {
    case leaf(PaneSpec)
    case split(SplitSpec)

    public var id: UUID {
        switch self {
        case .leaf(let pane): return pane.id
        case .split(let split): return split.id
        }
    }

    public var leafCount: Int {
        switch self {
        case .leaf:
            return 1
        case .split(let spec):
            return spec.first.leafCount + spec.second.leafCount
        }
    }

    public var allLeaves: [PaneSpec] {
        switch self {
        case .leaf(let pane):
            return [pane]
        case .split(let spec):
            return spec.first.allLeaves + spec.second.allLeaves
        }
    }

    public var allSplits: [SplitSpec] {
        switch self {
        case .leaf:
            return []
        case .split(let spec):
            return [spec] + spec.first.allSplits + spec.second.allSplits
        }
    }

    public var firstLeaf: PaneSpec {
        switch self {
        case .leaf(let pane):
            return pane
        case .split(let spec):
            return spec.first.firstLeaf
        }
    }

    public var focusedLeafID: UUID? {
        allLeaves.first(where: { $0.focus })?.id
    }

    public func leaf(withID id: UUID) -> PaneSpec? {
        switch self {
        case .leaf(let pane):
            return pane.id == id ? pane : nil
        case .split(let spec):
            return spec.first.leaf(withID: id) ?? spec.second.leaf(withID: id)
        }
    }

    /// Splits the leaf matching `leafID` into a new split with the original leaf first and `newPane` second.
    public func splitting(
        leafID: UUID,
        direction: SplitDirection,
        ratio: Double = 0.5,
        newPane: PaneSpec = PaneSpec(title: "New Pane")
    ) -> PaneNode {
        switch self {
        case .leaf(let pane):
            guard pane.id == leafID else { return self }
            return .split(
                SplitSpec(
                    direction: direction,
                    ratio: ratio,
                    first: .leaf(pane),
                    second: .leaf(newPane)
                )
            )
        case .split(let spec):
            return .split(
                SplitSpec(
                    id: spec.id,
                    direction: spec.direction,
                    ratio: spec.ratio,
                    first: spec.first.splitting(leafID: leafID, direction: direction, ratio: ratio, newPane: newPane),
                    second: spec.second.splitting(leafID: leafID, direction: direction, ratio: ratio, newPane: newPane)
                )
            )
        }
    }

    /// Removes the leaf matching `leafID`, collapsing its parent split cleanly.
    /// Returns `nil` only if the root itself is the removed leaf.
    public func removing(leafID: UUID) -> PaneNode? {
        switch self {
        case .leaf(let pane):
            return pane.id == leafID ? nil : self
        case .split(let spec):
            let updatedFirst = spec.first.removing(leafID: leafID)
            let updatedSecond = spec.second.removing(leafID: leafID)
            switch (updatedFirst, updatedSecond) {
            case (.none, .none):
                return nil
            case (.some(let remaining), .none):
                return remaining
            case (.none, .some(let remaining)):
                return remaining
            case (.some(let first), .some(let second)):
                return .split(
                    SplitSpec(
                        id: spec.id,
                        direction: spec.direction,
                        ratio: spec.ratio,
                        first: first,
                        second: second
                    )
                )
            }
        }
    }

    public func updating(leafID: UUID, transform: (inout PaneSpec) -> Void) -> PaneNode {
        switch self {
        case .leaf(var pane):
            if pane.id == leafID {
                transform(&pane)
            }
            return .leaf(pane)
        case .split(let spec):
            return .split(
                SplitSpec(
                    id: spec.id,
                    direction: spec.direction,
                    ratio: spec.ratio,
                    first: spec.first.updating(leafID: leafID, transform: transform),
                    second: spec.second.updating(leafID: leafID, transform: transform)
                )
            )
        }
    }

    /// Ensures only `leafID` has `focus = true` across this tree.
    public func settingFocus(leafID: UUID?) -> PaneNode {
        switch self {
        case .leaf(var pane):
            pane.focus = (pane.id == leafID)
            return .leaf(pane)
        case .split(let spec):
            return .split(
                SplitSpec(
                    id: spec.id,
                    direction: spec.direction,
                    ratio: spec.ratio,
                    first: spec.first.settingFocus(leafID: leafID),
                    second: spec.second.settingFocus(leafID: leafID)
                )
            )
        }
    }

    public func updatingRatio(splitID: UUID, ratio: Double) -> PaneNode {
        switch self {
        case .leaf:
            return self
        case .split(let spec):
            let newRatio = spec.id == splitID ? SplitSpec.clampedRatio(ratio) : spec.ratio
            return .split(
                SplitSpec(
                    id: spec.id,
                    direction: spec.direction,
                    ratio: newRatio,
                    first: spec.first.updatingRatio(splitID: splitID, ratio: ratio),
                    second: spec.second.updatingRatio(splitID: splitID, ratio: ratio)
                )
            )
        }
    }

    public func togglingSplitDirection(splitID: UUID) -> PaneNode {
        switch self {
        case .leaf:
            return self
        case .split(let spec):
            let newDirection: SplitDirection = spec.id == splitID
                ? (spec.direction == .columns ? .rows : .columns)
                : spec.direction
            return .split(
                SplitSpec(
                    id: spec.id,
                    direction: newDirection,
                    ratio: spec.ratio,
                    first: spec.first.togglingSplitDirection(splitID: splitID),
                    second: spec.second.togglingSplitDirection(splitID: splitID)
                )
            )
        }
    }

    /// Deep clones the tree with fresh UUIDs (useful when duplicating a layout).
    public func clonedWithFreshIDs() -> PaneNode {
        switch self {
        case .leaf(let pane):
            return .leaf(
                PaneSpec(
                    id: UUID(),
                    title: pane.title,
                    workingDirectory: pane.workingDirectory,
                    commands: pane.commands,
                    environment: pane.environment.map { EnvEntry(id: UUID(), key: $0.key, value: $0.value) },
                    profile: pane.profile,
                    delaySeconds: pane.delaySeconds,
                    focus: pane.focus
                )
            )
        case .split(let spec):
            return .split(
                SplitSpec(
                    id: UUID(),
                    direction: spec.direction,
                    ratio: spec.ratio,
                    first: spec.first.clonedWithFreshIDs(),
                    second: spec.second.clonedWithFreshIDs()
                )
            )
        }
    }
}
