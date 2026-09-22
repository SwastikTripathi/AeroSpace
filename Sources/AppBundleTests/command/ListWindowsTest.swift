@testable import AppBundle
import Common
import XCTest

@MainActor
final class ListWindowsTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertEquals(parseCommand("list-windows --pid 1").errorOrNil, "Mandatory option is not specified (--focused|--all|--monitor|--workspace)")
        assertNil(parseCommand("list-windows --workspace M --pid 1").errorOrNil)
        assertEquals(parseCommand("list-windows --pid 1 --focused").errorOrNil, "--focused conflicts with other \"filtering\" flags")
        assertEquals(parseCommand("list-windows --pid 1 --all").errorOrNil, "--all conflicts with \"filtering\" flags. Please use '--monitor all' instead of '--all' alias")
        assertNil(parseCommand("list-windows --all").errorOrNil)
        assertEquals(parseCommand("list-windows --all --workspace M").errorOrNil, "ERROR: Conflicting options: --all, --workspace")
        assertEquals(parseCommand("list-windows --all --focused").errorOrNil, "ERROR: Conflicting options: --all, --focused")
        assertEquals(parseCommand("list-windows --all --count --format %{window-title}").errorOrNil, "ERROR: Conflicting options: --count, --format")
        assertEquals(
            parseCommand("list-windows --all --focused --monitor mouse").errorOrNil,
            "ERROR: Conflicting options: --all, --focused")
        assertEquals(
            parseCommand("list-windows --all --focused --monitor mouse --workspace focused").errorOrNil,
            "ERROR: Conflicting options: --all, --focused, --workspace")
        assertEquals(
            parseCommand("list-windows --all --workspace focused").errorOrNil,
            "ERROR: Conflicting options: --all, --workspace")
        assertNil(parseCommand("list-windows --monitor mouse").errorOrNil)

        // --json
        assertEquals(parseCommand("list-windows --all --count --json").errorOrNil, "ERROR: Conflicting options: --count, --json")
        assertEquals(parseCommand("list-windows --all --format '%{right-padding}' --json").errorOrNil, "%{right-padding} interpolation variable is not allowed when --json is used")
        assertEquals(parseCommand("list-windows --all --format '%{window-title} |' --json").errorOrNil, "Only interpolation variables and spaces are allowed in \'--format\' when \'--json\' is used")
        assertNil(parseCommand("list-windows --all --format '%{window-title}' --json").errorOrNil)

        // --sort-by
        assertNil(parseCommand("list-windows --all --sort-by dfs --format '%{window-title}' --json").errorOrNil)
        assertEquals(
            (parseCommand("list-windows --all --sort-by window-title dfs pid").cmdOrNil?.flatten().singleOrNil() as? ListWindowsCommand)?.args.sortBy,
            [.windowTitle, .dfs, .pid],
        )
        assertEquals(parseCommand("list-windows --all --count --sort-by dfs").errorOrNil, "ERROR: Conflicting options: --count, --sort-by")
        assertEquals(
            parseCommand("list-windows --all --sort-by").errorOrNil,
            "ERROR: <sort-key>... is mandatory. Possible values: (dfs|pid|window-id|window-title|app-name)",
        )
        assertEquals(
            parseCommand("list-windows --all --sort-by dfs foo").errorOrNil,
            """
            ERROR: Can't parse 'foo'.
                   Possible values: (dfs|pid|window-id|window-title|app-name)
            """,
        )
    }

    func testInterpolationVariablesConsistency() {
        for kind in AeroObjKind.allCases {
            switch kind {
                case .window:
                    assertTrue(FormatVar.WindowFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "window-") })
                case .app:
                    assertTrue(FormatVar.AppFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "app-") })
                case .workspace:
                    assertTrue(FormatVar.WorkspaceFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "workspace") })
                case .monitor:
                    assertTrue(FormatVar.MonitorFormatVar.allCases.allSatisfy { $0.rawValue.starts(with: "monitor-") })
            }
        }
    }

    func testFormat() {
        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(.forTest(window: TestWindow.new(id: 2, parent: $0), title: "non-empty")),
                AeroObj.window(.forTest(window: TestWindow.new(id: 1, parent: $0), title: "")),
            ]
            assertSucc(windows.format([.interVar(.formatVar(.window(.windowTitle)))]), ["non-empty", ""])
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(.forTest(window: TestWindow.new(id: 2, parent: $0), title: "non-empty")),
                AeroObj.window(.forTest(window: TestWindow.new(id: 10, parent: $0), title: "")),
            ]
            assertSucc(windows.format([.interVar(.formatVar(.window(.windowId))), .interVar(.plainInterVar(.rightPadding)), .interVar(.formatVar(.window(.windowTitle)))]), ["2 non-empty", "10"])
        }

        Workspace.get(byName: name).rootTilingContainer.apply {
            let windows = [
                AeroObj.window(.forTest(window: TestWindow.new(id: 2, parent: $0), title: "title1")),
                AeroObj.window(.forTest(window: TestWindow.new(id: 10, parent: $0), title: "title2")),
            ]
            assertSucc(windows.format([.interVar(.formatVar(.window(.windowId))), .interVar(.plainInterVar(.rightPadding)), .literal(" | "), .interVar(.formatVar(.window(.windowTitle)))]), ["2  | title1", "10 | title2"])
        }
    }

    func testRunFocusedNoWindow() async {
        let result = await parseCommand("list-windows --focused --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, [noWindowIsFocused])
        assertEquals(result.stdout, [])
    }

    func testRunFocusedHappy() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }
        let result = await parseCommand("list-windows --focused --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, ["1"])
    }

    func testRunAll() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        let result = await parseCommand("list-windows --all --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, ["1", "2"])
    }

    func testRunDefaultOrder() async {
        let zApp = TestApp(pid: 10, name: "z-app")
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0, app: zApp)
            TestWindow.new(id: 10, parent: $0)
            TestWindow.new(id: 3, parent: $0)
            TestWindow.new(id: 1, parent: $0, app: zApp)
        }
        // By app name, then by window title, then by window ID
        let withTitles = await parseCommand("list-windows --all --format '%{window-id} %{window-title}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(withTitles.exitCode.rawValue, 0)
        assertEquals(withTitles.stdout, ["10 TestWindow(10)", "3 TestWindow(3)", "1 TestWindow(1)", "2 TestWindow(2)"])

        // Window titles aren't taken into account if they aren't requested in --format
        let withoutTitles = await parseCommand("list-windows --all --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(withoutTitles.exitCode.rawValue, 0)
        assertEquals(withoutTitles.stdout, ["3", "10", "1", "2"])
    }

    func testRunCount() async {
        let workspace = Workspace.get(byName: "a")
        TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 2, parent: workspace.rootTilingContainer)
        TestWindow.new(id: 3, parent: Workspace.get(byName: "b").rootTilingContainer)
        let result = await parseCommand("list-windows --all --count").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["3"])
    }

    func testRunJson() async {
        TestWindow.new(id: 7, parent: Workspace.get(byName: "a").rootTilingContainer)
        let result = await parseCommand("list-windows --all --format '%{window-id}' --json").cmdOrDie.run(.defaultEnv, .emptyStdin)
        let expected = JSONEncoder.aeroSpaceDefault.encodeToString([["window-id": 7]])
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, [expected])
    }

    func testRunFilterByWorkspaceName() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        let result = await parseCommand("list-windows --workspace a --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["1"])
    }

    func testRunFilterByWorkspaceFocused() async {
        let workspaceA = Workspace.get(byName: "a")
        TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        assertEquals(workspaceA.focusWorkspace(), true)
        let result = await parseCommand("list-windows --workspace focused --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["1"])
    }

    func testRunFilterByWorkspaceVisible() async {
        let workspaceA = Workspace.get(byName: "a")
        TestWindow.new(id: 1, parent: workspaceA.rootTilingContainer)
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        assertEquals(workspaceA.focusWorkspace(), true)
        let result = await parseCommand("list-windows --workspace visible --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["1"])
    }

    func testRunFilterByMonitor() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        let result = await parseCommand("list-windows --monitor focused --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stdout, ["1"])
    }

    func testRunInvalidMonitor() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        let result = await parseCommand("list-windows --monitor 99 --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stdout, [])
        assertEquals(result.stderr, ["Invalid monitor ID: 99"])
    }

    func testRunFilterByPid() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        let matching = await parseCommand("list-windows --monitor all --pid 0 --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(matching.exitCode.rawValue, 0)
        assertEquals(matching.stdout, ["1"])

        let mismatching = await parseCommand("list-windows --monitor all --pid 9999 --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(mismatching.exitCode.rawValue, 0)
        assertEquals(mismatching.stdout, [])
    }

    func testRunFilterByAppBundleId() async {
        TestWindow.new(id: 1, parent: Workspace.get(byName: "a").rootTilingContainer)
        let matching = await parseCommand("list-windows --monitor all --app-bundle-id bobko.AeroSpace.test-app --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(matching.exitCode.rawValue, 0)
        assertEquals(matching.stdout, ["1"])

        let mismatching = await parseCommand("list-windows --monitor all --app-bundle-id com.unknown.app --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(mismatching.exitCode.rawValue, 0)
        assertEquals(mismatching.stdout, [])
    }

    func testRunSortByWindowId() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
            TestWindow.new(id: 10, parent: $0)
            TestWindow.new(id: 2, parent: $0)
        }
        let result = await parseCommand("list-windows --all --sort-by window-id --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, ["2", "3", "10"])
    }

    func testRunSortByWindowTitle() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
            TestWindow.new(id: 10, parent: $0)
            TestWindow.new(id: 2, parent: $0)
        }
        // The title is fetched even though it's not part of --format
        let result = await parseCommand("list-windows --all --sort-by window-title --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, ["10", "2", "3"]) // TestWindow(10) < TestWindow(2) < TestWindow(3)
    }

    func testRunSortByPid() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0, app: TestApp(pid: 20, name: "a-app"))
            TestWindow.new(id: 2, parent: $0, app: TestApp(pid: 10, name: "z-app"))
            TestWindow.new(id: 3, parent: $0) // pid 0
        }
        let result = await parseCommand("list-windows --all --sort-by pid --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, ["3", "2", "1"])
    }

    func testRunSortByAppName() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0, app: TestApp(pid: 10, name: "z-app"))
            TestWindow.new(id: 2, parent: $0) // bobko.AeroSpace.test-app
            TestWindow.new(id: 3, parent: $0, app: TestApp(pid: 20, name: "a-app"))
        }
        let result = await parseCommand("list-windows --all --sort-by app-name --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, ["3", "2", "1"])
    }

    func testRunSortByMultipleKeys() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 3, parent: $0)
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
        }
        // All windows belong to the same app. Ties are broken by the next key
        let byDfs = await parseCommand("list-windows --all --sort-by app-name pid dfs --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(byDfs.exitCode.rawValue, 0)
        assertEquals(byDfs.stdout, ["3", "1", "2"])

        // Ties are broken by window ID
        let byWindowId = await parseCommand("list-windows --all --sort-by app-name pid --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(byWindowId.exitCode.rawValue, 0)
        assertEquals(byWindowId.stdout, ["1", "2", "3"])
    }

    func testRunSortByDfs() async {
        Workspace.get(byName: "10").rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
        }
        Workspace.get(byName: "b").rootTilingContainer.apply {
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        Workspace.get(byName: "a").rootTilingContainer.apply {
            TestWindow.new(id: 7, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TestWindow.new(id: 6, parent: $0)
                TestWindow.new(id: 5, parent: $0)
            }
            TestWindow.new(id: 4, parent: $0)
        }
        Workspace.get(byName: "2").rootTilingContainer.apply {
            TestWindow.new(id: 8, parent: $0)
        }
        let result = await parseCommand("list-windows --all --sort-by dfs --format '%{workspace} %{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, ["2 8", "10 1", "a 7", "a 6", "a 5", "a 4", "b 2", "b 3"])
    }

    func testRunSortByDfsWindowsThatAreNotPartOfTheTree() async {
        Workspace.get(byName: "a").apply {
            TestWindow.new(id: 3, parent: $0.macOsNativeFullscreenWindowsContainer)
            TestWindow.new(id: 4, parent: $0.rootTilingContainer)
            TestWindow.new(id: 1, parent: $0.macOsNativeHiddenAppsWindowsContainer)
        }
        TestWindow.new(id: 2, parent: Workspace.get(byName: "b").rootTilingContainer)
        let result = await parseCommand("list-windows --all --sort-by dfs --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, ["4", "3", "1", "2"])
    }

    func testRunSortByDfsFloatingWindows() async {
        let workspace = Workspace.get(byName: name)
        func tiling(_ id: UInt32, _ parent: TilingContainer, _ rect: Rect) {
            TestWindow.new(id: id, parent: parent, rect: rect).lastAppliedLayoutVirtualRect = rect
        }
        workspace.rootTilingContainer.apply {
            tiling(1, $0, Rect(topLeftX: 0, topLeftY: 0, width: 100, height: 100))
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                $0.lastAppliedLayoutVirtualRect = Rect(topLeftX: 100, topLeftY: 0, width: 100, height: 100)
                tiling(2, $0, Rect(topLeftX: 100, topLeftY: 0, width: 100, height: 50))
                tiling(3, $0, Rect(topLeftX: 100, topLeftY: 50, width: 100, height: 50))
            }
        }
        workspace.floatingWindowsContainer.apply {
            TestWindow.new(id: 4, parent: $0, rect: Rect(topLeftX: 140, topLeftY: 10, width: 20, height: 20)) // Above the center of 2
            TestWindow.new(id: 5, parent: $0, rect: Rect(topLeftX: 140, topLeftY: 80, width: 20, height: 20)) // Below the center of 3
            TestWindow.new(id: 6, parent: $0, rect: Rect(topLeftX: 30, topLeftY: 40, width: 20, height: 20)) // To the left of the center of 1
            TestWindow.new(id: 7, parent: $0) // The position is unknown
        }
        TestWindow.new(id: 8, parent: workspace.macOsNativeFullscreenWindowsContainer)
        assertEquals(workspace.focusWorkspace(), true)
        let treeBefore = workspace.layoutDescription

        let result = await parseCommand("list-windows --workspace focused --sort-by dfs --format '%{window-id}'").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, ["6", "1", "4", "2", "3", "5", "7", "8"])
        assertEquals(workspace.layoutDescription, treeBefore) // The tree isn't mutated

        // The order is consistent with focus --dfs-index
        for (dfsIndex, windowId) in result.stdout.prefix(6).enumerated() {
            assertEquals(await parseCommand("focus --dfs-index \(dfsIndex)").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
            assertEquals(focus.windowOrNil?.windowId.description, windowId)
        }
        assertEquals(await parseCommand("focus --dfs-index 6").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 2)
    }

    func testRunSortByDfsFloatingWindowsOfInvisibleWorkspace() async {
        let workspace = Workspace.get(byName: "b")
        func tiling(_ id: UInt32, _ rect: Rect) {
            let window = TestWindow.new(id: id, parent: workspace.rootTilingContainer, rect: rect)
            window.lastAppliedLayoutPhysicalRect = rect
            window.lastAppliedLayoutVirtualRect = rect
        }
        tiling(1, Rect(topLeftX: 0, topLeftY: 0, width: 960, height: 1080))
        tiling(2, Rect(topLeftX: 960, topLeftY: 0, width: 960, height: 1080))
        workspace.floatingWindowsContainer.apply {
            TestWindow.new(id: 3, parent: $0, rect: Rect(topLeftX: 100, topLeftY: 100, width: 50, height: 50)) // To the left of the center of 1
            TestWindow.new(id: 4, parent: $0, rect: Rect(topLeftX: 700, topLeftY: 100, width: 50, height: 50)) // To the right of the center of 1
        }
        let command = "list-windows --all --sort-by dfs --format '%{window-id}'"
        let expected = ["3", "1", "4", "2"]

        assertEquals(workspace.focusWorkspace(), true)
        assertEquals(await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin).stdout, expected)

        // Windows of invisible workspaces are hidden in the corner of the monitor. Their AX positions must not affect the order
        assertEquals(Workspace.get(byName: "a").focusWorkspace(), true)
        assertFalse(workspace.isVisible)
        for window in workspace.allLeafWindowsRecursive {
            (window as! TestWindow).hideInCornerForTest()
            assertTrue(window.isHiddenInCorner)
        }
        let result = await parseCommand(command).cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(result.stderr, [])
        assertEquals(result.stdout, expected)

        // The order is consistent with focus --dfs-index once the workspace is visible again
        for window in workspace.allLeafWindowsRecursive {
            (window as! TestWindow).unhideFromCornerForTest()
        }
        assertEquals(workspace.focusWorkspace(), true)
        for (dfsIndex, windowId) in expected.enumerated() {
            assertEquals(await parseCommand("focus --dfs-index \(dfsIndex)").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
            assertEquals(focus.windowOrNil?.windowId.description, windowId)
        }
    }
}
