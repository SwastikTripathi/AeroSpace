@testable import AppBundle
import Common
import XCTest

@MainActor
final class FocusMonitorCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertEquals(parseFocusMonitorTarget("focus-monitor next"), .relative(.next))
        assertEquals(parseFocusMonitorTarget("focus-monitor left"), .direction(.left))
        assertEquals(parseFocusMonitorTarget("focus-monitor main"), .patterns([.main]))
        assertEquals(parseCommand("focus-monitor --wrap-around main").errorOrNil, "--wrap-around is incompatible with <monitor-pattern> argument")
    }

    func testParseDashDash() {
        assertEquals(parseFocusMonitorTarget("focus-monitor -- next"), .patterns([.pattern("next")!]))
        assertEquals(parseFocusMonitorTarget("focus-monitor -- main 2"), .patterns([.main, .sequenceNumber(2)]))
        assertEquals(parseCommand("focus-monitor --").errorOrNil, "ERROR: Argument \'(left|down|up|right|next|prev|<monitor-pattern>)\' is mandatory")
    }

    func testFocusMonitorInDirection() async {
        let monitors = setUpMonitorsForTests([
            Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
        ])
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        assertTrue(monitors[1].setActiveWorkspace(Workspace.get(byName: "b")))

        await parseCommand("focus-monitor right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "b")

        await parseCommand("focus-monitor left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "a")
    }

    func testFocusMonitorInDirection_noMonitorInDirection() async {
        let monitors = setUpMonitorsForTests([
            Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
        ])
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        assertTrue(monitors[1].setActiveWorkspace(Workspace.get(byName: "b")))

        let result = await parseCommand("focus-monitor left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["No monitors in direction left"])
        assertEquals(focus.workspace.name, "a")

        await parseCommand("focus-monitor --wrap-around left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "b")
    }

    func testFocusMonitorInDirection_verticalMonitors() async {
        let monitors = setUpMonitorsForTests([
            Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            Rect(topLeftX: 0, topLeftY: 1080, width: 1920, height: 1080),
        ])
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        assertTrue(monitors[1].setActiveWorkspace(Workspace.get(byName: "b")))

        let result = await parseCommand("focus-monitor right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["No monitors in direction right"])
        assertEquals(focus.workspace.name, "a")

        await parseCommand("focus-monitor down").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "b")
    }

    func testFocusMonitorInDirection_focusesEdgeWindow() async {
        let monitors = setUpMonitorsForTests([
            Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
        ])
        let workspaceA = Workspace.get(byName: "a").apply {
            TestWindow.new(id: 1, parent: $0.rootTilingContainer)
        }
        assertTrue(workspaceA.focusWorkspace())
        let workspaceB = Workspace.get(byName: "b").apply {
            $0.rootTilingContainer.apply {
                TestWindow.new(id: 2, parent: $0)
                TestWindow.new(id: 3, parent: $0)
            }
        }
        assertTrue(monitors[1].setActiveWorkspace(workspaceB))
        assertEquals(workspaceB.mostRecentWindowRecursive?.windowId, 3) // The latest bound

        // The focus enters the right monitor from the left, so the left-most window is focused instead of the MRU one
        await parseCommand("focus-monitor right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)

        await parseCommand("focus-monitor left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)

        // Wrapping around to the left enters the right-most monitor from the right
        await parseCommand("focus-monitor --wrap-around left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
    }

    func testFocusMonitorInDirection_focusesEdgeWindow_verticalMonitors() async {
        let monitors = setUpMonitorsForTests([
            Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            Rect(topLeftX: 0, topLeftY: 1080, width: 1920, height: 1080),
        ])
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        let workspaceB = Workspace.get(byName: "b").apply {
            TilingContainer.newVTiles(parent: $0.rootTilingContainer, adaptiveWeight: 1).apply {
                TestWindow.new(id: 1, parent: $0)
                TestWindow.new(id: 2, parent: $0)
            }
        }
        assertTrue(monitors[1].setActiveWorkspace(workspaceB))
        assertEquals(workspaceB.mostRecentWindowRecursive?.windowId, 2) // The latest bound

        // The focus enters the bottom monitor from the top, so the top-most window is focused instead of the MRU one
        await parseCommand("focus-monitor down").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testFocusMonitorInDirection_floatingWindowsAreSeenAsTiling() async {
        let monitors = setUpMonitorsForTests([
            Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
        ])
        let workspaceA = Workspace.get(byName: "a").apply {
            TestWindow.new(id: 1, parent: $0.rootTilingContainer)
        }
        assertTrue(workspaceA.focusWorkspace())
        var window2: Window!
        let workspaceB = Workspace.get(byName: "b").apply {
            $0.floatingWindowsContainer.apply {
                window2 = TestWindow.new(id: 2, parent: $0, rect: Rect(topLeftX: 1940, topLeftY: 20, width: 100, height: 100))
                TestWindow.new(id: 3, parent: $0, rect: Rect(topLeftX: 3740, topLeftY: 20, width: 100, height: 100))
            }
        }
        assertTrue(monitors[1].setActiveWorkspace(workspaceB))
        assertEquals(workspaceB.mostRecentWindowRecursive?.windowId, 3) // The latest bound

        // The right monitor has no tiling windows. Still, its left-most floating window is focused
        await parseCommand("focus-monitor right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        assertTrue(window2.isFloating) // The window is restored back to floating
    }

    func testFocusMonitorNextPrevAndPatterns_focusMruWindow() async {
        let monitors = setUpMonitorsForTests([
            Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
        ])
        let workspaceA = Workspace.get(byName: "a").apply {
            TestWindow.new(id: 1, parent: $0.rootTilingContainer)
        }
        assertTrue(workspaceA.focusWorkspace())
        let workspaceB = Workspace.get(byName: "b").apply {
            $0.rootTilingContainer.apply {
                TestWindow.new(id: 2, parent: $0)
                TestWindow.new(id: 3, parent: $0)
            }
        }
        assertTrue(monitors[1].setActiveWorkspace(workspaceB))

        // Contrary to (left|down|up|right), next|prev and <monitor-pattern> keep focusing the MRU window
        await parseCommand("focus-monitor next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)

        await parseCommand("focus-monitor prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 1)

        await parseCommand("focus-monitor secondary").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
    }

    func testFocusMonitorNextPrev() async {
        let monitors = setUpMonitorsForTests([
            Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
            Rect(topLeftX: -1920, topLeftY: 0, width: 1920, height: 1080),
        ])
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        assertTrue(monitors[1].setActiveWorkspace(Workspace.get(byName: "b")))
        assertTrue(monitors[2].setActiveWorkspace(Workspace.get(byName: "c")))

        // Monitors are ordered from left to right: c, a, b
        await parseCommand("focus-monitor next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "b")

        let result = await parseCommand("focus-monitor next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["Can't find target monitor"])
        assertEquals(focus.workspace.name, "b")

        await parseCommand("focus-monitor --wrap-around next").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "c")

        await parseCommand("focus-monitor --wrap-around prev").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "b")
    }

    func testFocusMonitorPatterns() async {
        let monitors = setUpMonitorsForTests([
            Rect(topLeftX: 0, topLeftY: 0, width: 1920, height: 1080),
            Rect(topLeftX: 1920, topLeftY: 0, width: 1920, height: 1080),
        ])
        assertTrue(Workspace.get(byName: "a").focusWorkspace())
        assertTrue(monitors[1].setActiveWorkspace(Workspace.get(byName: "b")))

        await parseCommand("focus-monitor secondary").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "b")

        await parseCommand("focus-monitor main").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "a")

        await parseCommand("focus-monitor 'Test Monitor 2'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "b")

        await parseCommand("focus-monitor 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.workspace.name, "a")
    }
}

@MainActor
private func parseFocusMonitorTarget(_ raw: String) -> MonitorTarget? {
    guard case .cmd(.cmd(let cmd)) = parseCommand(raw),
          let args = cmd.args as? FocusMonitorCmdArgs
    else { return nil }
    return args.target.val
}
