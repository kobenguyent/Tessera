import Foundation
import Testing
@testable import TesseraCore

@Suite("Layout Geometry")
struct LayoutGeometryTests {
    @Test("2x2 quad grid computes four exact non-overlapping quadrants")
    func quadGridComputesExactNonOverlappingQuadrants() {
        let tree = MosaicStructureTemplate.quadGrid.makeTree()
        let screen = TesseraRect(x: 0, y: 0, width: 1000, height: 800)
        let frames = LayoutGeometry.computeFrames(root: tree, in: screen, gap: 0)

        #expect(frames.count == 4)
        #expect(frames[0].rect == TesseraRect(x: 0, y: 0, width: 500, height: 400))
        #expect(frames[1].rect == TesseraRect(x: 500, y: 0, width: 500, height: 400))
        #expect(frames[2].rect == TesseraRect(x: 0, y: 400, width: 500, height: 400))
        #expect(frames[3].rect == TesseraRect(x: 500, y: 400, width: 500, height: 400))
    }

    @Test("Columns split with gap respects split ratio")
    func columnsWithGapRespectsRatio() {
        let tree = PaneNode.split(SplitSpec(
            direction: .columns,
            ratio: 0.6,
            first: .leaf(PaneSpec(title: "Main")),
            second: .leaf(PaneSpec(title: "Side"))
        ))
        let frames = LayoutGeometry.computeFrames(
            root: tree,
            in: TesseraRect(x: 100, y: 50, width: 1010, height: 600),
            gap: 10
        )

        #expect(frames.count == 2)
        #expect(abs(frames[0].rect.x - 100) < 0.01)
        #expect(abs(frames[0].rect.width - 600) < 0.01)
        #expect(abs(frames[1].rect.x - 710) < 0.01)
        #expect(abs(frames[1].rect.width - 400) < 0.01)
    }

    @Test("Window frame presets resolve accurately inside screen bounds")
    func windowFramePresetsResolveProperly() throws {
        let screen = TesseraRect(x: 0, y: 25, width: 1600, height: 1000)
        #expect(WindowFramePreset.default.resolveRect(screen: screen) == nil)

        let left = try #require(WindowFramePreset.leftHalf.resolveRect(screen: screen))
        let right = try #require(WindowFramePreset.rightHalf.resolveRect(screen: screen))
        #expect(left.maxX < right.x)
        #expect(abs(left.width - right.width) < 0.01)

        let centered = try #require(WindowFramePreset.centeredLarge.resolveRect(screen: screen))
        #expect(centered.x > 0)
        #expect(centered.y > 25)
    }
}
