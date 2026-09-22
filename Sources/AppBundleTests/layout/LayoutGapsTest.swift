@testable import AppBundle
import Common
import XCTest

@MainActor
final class LayoutGapsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testOuterGapsInPercent() async throws {
        // 10% of the test monitor width (1920) is 192. 5% of its height (1080) is 54
        config.gaps = Gaps(
            inner: .zero,
            outer: .init(left: .percent(10), bottom: .pixels(0), top: .percent(5), right: .percent(10)),
        )
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)

        try await workspace.layoutWorkspace()
        assertEquals(window.lastAppliedLayoutPhysicalRect?.topLeftCorner, CGPoint(x: 192, y: 54))
        assertEquals(window.lastAppliedLayoutPhysicalRect?.size, CGSize(width: 1920 - 2 * 192, height: 1080 - 54 - 1))
    }

    func testInnerGapsInPercent() async throws {
        // 10% of the test monitor width (1920) is 192
        config.gaps = Gaps(inner: .init(vertical: .pixels(0), horizontal: .percent(10)), outer: .zero)
        let workspace = Workspace.get(byName: name)
        let window1 = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        let window2 = TestWindow.new(id: 2, parent: workspace.rootTilingContainer)

        // h_tiles. Both windows are 960 wide, and they give away a half of the gap each
        try await workspace.layoutWorkspace()
        assertEquals(window1.lastAppliedLayoutPhysicalRect?.topLeftCorner, CGPoint(x: 0, y: 0))
        assertEquals(window1.lastAppliedLayoutPhysicalRect?.size, CGSize(width: 960 - 96, height: 1079))
        assertEquals(window2.lastAppliedLayoutPhysicalRect?.topLeftCorner, CGPoint(x: 960 + 96, y: 0))
        assertEquals(window2.lastAppliedLayoutPhysicalRect?.size, CGSize(width: 960 - 96, height: 1079))
    }

    func testVerticalInnerGapsInPercentAreRelativeToTheMonitorHeight() async throws {
        // 10% of the test monitor height (1080) is 108
        config.gaps = Gaps(inner: .init(vertical: .percent(10), horizontal: .pixels(0)), outer: .zero)
        let workspace = Workspace.get(byName: name)
        var window1: Window!
        var window2: Window!
        TilingContainer.newVTiles(parent: workspace.rootTilingContainer, adaptiveWeight: 1).apply {
            window1 = TestWindow.new(id: 1, parent: $0)
            window2 = TestWindow.new(id: 2, parent: $0)
        }

        // v_tiles. Both windows are 539.5 tall, and they give away a half of the gap each
        try await workspace.layoutWorkspace()
        assertEquals(window1.lastAppliedLayoutPhysicalRect?.topLeftCorner, CGPoint(x: 0, y: 0))
        assertEquals(window1.lastAppliedLayoutPhysicalRect?.size, CGSize(width: 1920, height: 539.5 - 54))
        assertEquals(window2.lastAppliedLayoutPhysicalRect?.topLeftCorner, CGPoint(x: 0, y: 539.5 + 54))
        assertEquals(window2.lastAppliedLayoutPhysicalRect?.size, CGSize(width: 1920, height: 539.5 - 54))
    }
}
