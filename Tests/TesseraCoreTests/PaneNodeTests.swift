import Foundation
import Testing
@testable import TesseraCore

@Suite("PaneNode Tree Operations")
struct PaneNodeTests {
    @Test("Splitting and removing leaves collapses parent splits cleanly")
    func splittingAndRemovingCollapsesCleanly() {
        let p1 = PaneSpec(title: "Primary", focus: true)
        let p2 = PaneSpec(title: "Secondary")
        let p3 = PaneSpec(title: "Bottom Right")

        let root = PaneNode.leaf(p1)
            .splitting(leafID: p1.id, direction: .columns, ratio: 0.6, newPane: p2)
            .splitting(leafID: p2.id, direction: .rows, ratio: 0.5, newPane: p3)

        #expect(root.leafCount == 3)
        #expect(root.allLeaves.map(\.title) == ["Primary", "Secondary", "Bottom Right"])
        #expect(root.allSplits.count == 2)
        #expect(root.focusedLeafID == p1.id)

        let collapsed = root.removing(leafID: p3.id)
        #expect(collapsed != nil)
        #expect(collapsed?.leafCount == 2)
        #expect(collapsed?.allLeaves.map(\.id) == [p1.id, p2.id])
        #expect(collapsed?.allSplits.count == 1)

        let single = collapsed?.removing(leafID: p2.id)
        #expect(single?.leafCount == 1)
        #expect(single?.firstLeaf.id == p1.id)

        #expect(single?.removing(leafID: p1.id) == nil)
    }

    @Test("Split ratio clamps to 0.15...0.85 and direction toggles")
    func ratioClampingAndDirectionToggle() {
        let splitID = UUID()
        let root = PaneNode.split(SplitSpec(
            id: splitID,
            direction: .columns,
            ratio: 0.99,
            first: .leaf(PaneSpec(title: "A")),
            second: .leaf(PaneSpec(title: "B"))
        ))

        #expect(root.allSplits.first?.ratio == 0.85)

        let updatedLow = root.updatingRatio(splitID: splitID, ratio: 0.01)
        #expect(updatedLow.allSplits.first?.ratio == 0.15)

        let toggled = updatedLow.togglingSplitDirection(splitID: splitID)
        #expect(toggled.allSplits.first?.direction == .rows)
    }

    @Test("Setting focus clears focus on all other panes")
    func focusExclusivity() {
        let p1 = PaneSpec(title: "A", focus: true)
        let p2 = PaneSpec(title: "B", focus: false)
        let tree = PaneNode.split(SplitSpec(direction: .columns, first: .leaf(p1), second: .leaf(p2)))

        let refocused = tree.settingFocus(leafID: p2.id)
        #expect(refocused.leaf(withID: p1.id)?.focus == false)
        #expect(refocused.leaf(withID: p2.id)?.focus == true)
        #expect(refocused.focusedLeafID == p2.id)
    }

    @Test("Duplicating a layout generates fresh UUIDs for layout and every pane")
    func cloneGeneratesFreshIDs() {
        let original = BuiltInPresets.quadMosaic()
        let copy = original.duplicated(newName: "My Quad")
        #expect(original.id != copy.id)
        #expect(copy.name == "My Quad")
        #expect(!copy.isBuiltIn)

        let origIDs = Set(original.tabs.flatMap { $0.root.allLeaves.map(\.id) })
        let copyIDs = Set(copy.tabs.flatMap { $0.root.allLeaves.map(\.id) })
        #expect(origIDs.isDisjoint(with: copyIDs))
    }

    @Test("Structure templates preserve existing pane titles and commands")
    func templatesPreserveExistingCommands() {
        let existing = [
            PaneSpec(title: "Web", commands: ["npm run dev"]),
            PaneSpec(title: "API", commands: ["go run ."])
        ]
        let quad = MosaicStructureTemplate.quadGrid.makeTree(preserving: existing)
        #expect(quad.leafCount == 4)
        #expect(quad.allLeaves[0].title == "Web")
        #expect(quad.allLeaves[0].commands == ["npm run dev"])
        #expect(quad.allLeaves[1].title == "API")
        #expect(quad.allLeaves[1].commands == ["go run ."])
    }
}
