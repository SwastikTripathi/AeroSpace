@testable import AppBundle
import Common
import XCTest

@MainActor
final class LayoutAccordionTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testAccordionPaddingInPixels() async throws {
        config.accordionPadding = .pixels(30)
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .accordion
        TestWindow.new(id: 1, parent: root)
        let window2 = TestWindow.new(id: 2, parent: root)
        TestWindow.new(id: 3, parent: root)
        window2.markAsMostRecentChild()

        try await workspace.layoutWorkspace()
        assertEquals(window2.lastAppliedLayoutPhysicalRect?.topLeftCorner, CGPoint(x: 30, y: 0))
        assertEquals(window2.lastAppliedLayoutPhysicalRect?.size, CGSize(width: 1920 - 2 * 30, height: 1079))
    }

    func testAccordionPaddingInPercent() async throws {
        config.accordionPadding = .percent(10)
        let workspace = Workspace.get(byName: name)
        let root = workspace.rootTilingContainer
        root.layout = .accordion
        let window1 = TestWindow.new(id: 1, parent: root)
        let window2 = TestWindow.new(id: 2, parent: root)
        let window3 = TestWindow.new(id: 3, parent: root)
        window2.markAsMostRecentChild()

        // h_accordion. 10% of the test monitor width (1920) is 192
        try await workspace.layoutWorkspace()
        assertEquals(window1.lastAppliedLayoutPhysicalRect?.topLeftCorner, CGPoint(x: 0, y: 0))
        assertEquals(window1.lastAppliedLayoutPhysicalRect?.size, CGSize(width: 1920 - 192, height: 1079))
        assertEquals(window2.lastAppliedLayoutPhysicalRect?.topLeftCorner, CGPoint(x: 192, y: 0))
        assertEquals(window2.lastAppliedLayoutPhysicalRect?.size, CGSize(width: 1920 - 2 * 192, height: 1079))
        assertEquals(window3.lastAppliedLayoutPhysicalRect?.topLeftCorner, CGPoint(x: 192, y: 0))
        assertEquals(window3.lastAppliedLayoutPhysicalRect?.size, CGSize(width: 1920 - 192, height: 1079))

        // v_accordion. 10% of the test monitor height (1080) is 108
        root.changeOrientation(.v)
        try await workspace.layoutWorkspace()
        assertEquals(window2.lastAppliedLayoutPhysicalRect?.topLeftCorner, CGPoint(x: 0, y: 108))
        assertEquals(window2.lastAppliedLayoutPhysicalRect?.size, CGSize(width: 1920, height: 1079 - 2 * 108))
    }
}
