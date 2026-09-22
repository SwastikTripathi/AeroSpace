@testable import AppBundle
import Common
import XCTest

@MainActor
final class MacosNativeFullscreenCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testFloatingWindowIsStillFloatingAfterExitingFullscreen() async {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
        assertEquals(window.focusWindow(), true)

        await parseCommand("macos-native-fullscreen on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.isMacosFullscreenForTest, true)
        assertEquals(window.parent?.kind, .macosFullscreenWindowsContainer)
        assertEquals(window.layoutReason, .macos(prevParentKind: .floatingWindowsContainer))

        await parseCommand("macos-native-fullscreen off").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.isMacosFullscreenForTest, false)
        assertEquals(workspace.floatingWindows.map(\.windowId), [1])
        assertEquals(window.layoutReason, .standard)
    }

    func testTilingWindowIsStillTilingAfterExitingFullscreen() async {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.rootTilingContainer)
        assertEquals(window.focusWindow(), true)

        await parseCommand("macos-native-fullscreen on").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.isMacosFullscreenForTest, true)
        assertEquals(window.parent?.kind, .macosFullscreenWindowsContainer)
        assertEquals(window.layoutReason, .macos(prevParentKind: .tilingContainer))

        await parseCommand("macos-native-fullscreen off").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.isMacosFullscreenForTest, false)
        assertEquals(workspace.rootTilingContainer.layoutDescription, .h_tiles([.window(1)]))
        assertEquals(window.layoutReason, .standard)
    }
}
