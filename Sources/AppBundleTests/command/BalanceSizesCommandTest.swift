@testable import AppBundle
import Common
import XCTest

@MainActor
final class BalanceSizesCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testBalanceSizesCommand() async {
        let workspace = Workspace.get(byName: name).apply { wsp in
            wsp.rootTilingContainer.apply {
                TestWindow.new(id: 1, parent: $0).setWeight(wsp.rootTilingContainer.orientation, 1)
                TestWindow.new(id: 2, parent: $0).setWeight(wsp.rootTilingContainer.orientation, 2)
                TestWindow.new(id: 3, parent: $0).setWeight(wsp.rootTilingContainer.orientation, 3)
            }
        }

        await parseCommand("balance-sizes").cmdOrDie
            .run(.defaultEnv.withWorkspaceName(name), .emptyStdin)

        for window in workspace.rootTilingContainer.children {
            // The total weight of 1 + 2 + 3 is spread equally across the 3 children
            assertEquals(window.getWeight(workspace.rootTilingContainer.orientation), 2)
        }
    }

    func testBalanceSizes_everyContainerKeepsItsOwnTotalWeight() async {
        var window1: Window!
        var window2: Window!
        var window3: Window!
        var vTiles: TilingContainer!
        Workspace.get(byName: name).rootTilingContainer.apply {
            window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 100)
            vTiles = TilingContainer.newVTiles(parent: $0, adaptiveWeight: 300).apply {
                window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 100)
                window3 = TestWindow.new(id: 3, parent: $0, adaptiveWeight: 500)
            }
        }

        await parseCommand("balance-sizes").cmdOrDie
            .run(.defaultEnv.withWorkspaceName(name), .emptyStdin)

        // The root container keeps its own total of 100 + 300
        assertEquals(window1.hWeight, 200)
        assertEquals(vTiles.hWeight, 200)
        // The nested container keeps its own total of 100 + 500
        assertEquals(window2.vWeight, 300)
        assertEquals(window3.vWeight, 300)
    }

    func testBalanceSizes_accordionWeightsAreUntouched() async {
        var window1: Window!
        var window2: Window!
        Workspace.get(byName: name).rootTilingContainer.apply {
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                $0.layout = .accordion
                window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 100)
                window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 500)
            }
        }

        await parseCommand("balance-sizes").cmdOrDie
            .run(.defaultEnv.withWorkspaceName(name), .emptyStdin)

        assertEquals(window1.vWeight, 100)
        assertEquals(window2.vWeight, 500)
    }

    func testBalanceSizesThenResize_isTheSameAsResizeAlone() async {
        var window1: Window!
        var window2: Window!
        Workspace.get(byName: name).rootTilingContainer.apply {
            window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 300)
            window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 700)
        }
        assertEquals(window1.focusWindow(), true)

        // Commands of a single binding run before the layout pass converts weights into real sizes. That's why
        // resize must observe the weights that balance-sizes has left behind
        await parseCommand("balance-sizes; resize width 200").cmdOrDie.run(.defaultEnv, .emptyStdin)

        // balance-sizes makes it 500/500. diff = 200 - 500 = -300, childDiff = -300 / (2 - 1) = -300
        assertEquals(window1.hWeight, 200)
        assertEquals(window2.hWeight, 800)
    }

    func testResizeAlone_producesTheSameResultAsTheChainedCommandList() async {
        var window1: Window!
        var window2: Window!
        Workspace.get(byName: name).rootTilingContainer.apply {
            window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 500)
            window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 500)
        }
        assertEquals(window1.focusWindow(), true)

        await parseCommand("resize width 200").cmdOrDie.run(.defaultEnv, .emptyStdin)

        assertEquals(window1.hWeight, 200)
        assertEquals(window2.hWeight, 800)
    }
}
