@testable import AppBundle
import Common
import XCTest

@MainActor
final class FocusBackAndForthCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testBackAndForth() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        await parseCommand("focus --window-id 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("focus --window-id 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("focus --window-id 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)

        await parseCommand("focus-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
        await parseCommand("focus-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
        await parseCommand("focus-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testPrevWindowIsClosed() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }
        await parseCommand("focus --window-id 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("focus --window-id 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("focus --window-id 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("close --window-id 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)

        let result = await parseCommand("focus-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 1)

        await parseCommand("focus-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 3)
    }

    func testSeveralPrevWindowsAreClosed() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
            TestWindow.new(id: 4, parent: $0)
        }
        await parseCommand("focus --window-id 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("focus --window-id 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("focus --window-id 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("focus --window-id 4").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("close --window-id 3").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("close --window-id 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 4)

        let result = await parseCommand("focus-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testEmptyWorkspaceIsRemembered() async {
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
        }
        await parseCommand("workspace a").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("focus --window-id 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("focus --window-id 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("close --window-id 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)

        let result = await parseCommand("focus-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(focus.workspace.name, "a")
        assertNil(focus.windowOrNil)
    }

    func testAllPrevWindowsAreClosed_fails() async {
        // The windows are in the initially focused workspace, so its history element resolves to the current focus (window 2)
        focus.workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TestWindow.new(id: 2, parent: $0)
        }
        await parseCommand("focus --window-id 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("focus --window-id 2").cmdOrDie.run(.defaultEnv, .emptyStdin)
        await parseCommand("close --window-id 1").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(focus.windowOrNil?.windowId, 2)

        let result = await parseCommand("focus-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["No previously focused window or workspace to switch focus to"])
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testEmptyHistory_fails() async {
        let result = await parseCommand("focus-back-and-forth").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["No previously focused window or workspace to switch focus to"])
    }
}
