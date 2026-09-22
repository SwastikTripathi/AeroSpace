@testable import AppBundle
import Common
import XCTest

@MainActor
final class MacosNativeMinimizeCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testFloatingWindowIsRememberedAsFloating() async {
        let workspace = Workspace.get(byName: name)
        let window = TestWindow.new(id: 1, parent: workspace.floatingWindowsContainer)
        assertEquals(window.focusWindow(), true)

        await parseCommand("macos-native-minimize").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window.isMacosMinimizedForTest, true)
        assertEquals(window.parent?.kind, .macosMinimizedWindowsContainer)
        assertEquals(window.layoutReason, .macos(prevParentKind: .floatingWindowsContainer))

        window.unbindFromParent() // macosMinimizedWindowsContainer is global. Don't leak the window to other tests
    }
}
