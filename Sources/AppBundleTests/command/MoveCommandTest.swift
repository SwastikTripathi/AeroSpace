@testable import AppBundle
import AppKit
import Common
import XCTest

@MainActor
final class MoveCommandTest: XCTestCase {
    override func setUp() async throws { setUpWorkspacesForTests() }

    func testParse() {
        assertNil(parseCommand("move --fail-if-fullscreen left").errorOrNil)
        assertNil(parseCommand("move --fail-if-macos-native-fullscreen --window-id 1 right").errorOrNil)
        assertNil(parseCommand("move --floating-pixels 50 left").errorOrNil)
        assertEquals(
            parseCommand("move --floating-pixels foo left").errorOrNil,
            "ERROR: Failed to parse 'foo' CLI argument: Can't convert 'foo' to UInt32",
        )
    }

    func testFailIfFullscreen() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            let window = TestWindow.new(id: 1, parent: $0)
            assertEquals(window.focusWindow(), true)
            window.isFullscreen = true
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("move --fail-if-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
    }

    func testFailIfMacosNativeFullscreen() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            let window = TestWindow.new(id: 1, parent: $0)
            assertEquals(window.focusWindow(), true)
            window.isMacosFullscreenForTest = true
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("move --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(root.layoutDescription, .h_tiles([.window(1), .window(2)]))
    }

    func testFailIfFullscreenAllowsRegularWindows() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("move --fail-if-fullscreen --fail-if-macos-native-fullscreen right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(root.layoutDescription, .h_tiles([.window(2), .window(1)]))
    }

    func testMove_swapWindows() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(root.layoutDescription, .h_tiles([.window(2), .window(1)]))
    }

    func testMoveInto_findTopMostContainerWithRightOrientation() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                }
            }
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            root.layoutDescription,
            .h_tiles([
                .window(0),
                .h_tiles([
                    .window(1),
                    .h_tiles([
                        .window(2),
                    ]),
                ]),
            ]),
        )
    }

    func testMove_mru() async {
        var window3: Window!
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0)
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                TilingContainer.newHTiles(parent: $0, adaptiveWeight: 1).apply {
                    TestWindow.new(id: 2, parent: $0)
                    window3 = TestWindow.new(id: 3, parent: $0)
                }
                TestWindow.new(id: 4, parent: $0)
            }
        }
        window3.markAsMostRecentChild()

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            root.layoutDescription,
            .h_tiles([
                .window(0),
                .v_tiles([
                    .h_tiles([
                        .window(1),
                        .window(2),
                        .window(3),
                    ]),
                    .window(4),
                ]),
            ]),
        )
    }

    func testSwap_preserveWeight() async {
        let root = Workspace.get(byName: name).rootTilingContainer
        let window1 = TestWindow.new(id: 1, parent: root, adaptiveWeight: 1)
        let window2 = TestWindow.new(id: 2, parent: root, adaptiveWeight: 2)
        _ = window2.focusWindow()

        await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window2.hWeight, 2)
        assertEquals(window1.hWeight, 1)
    }

    func testMoveIn_newWeight() async {
        var window1: Window!
        var window2: Window!
        Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 0, parent: $0, adaptiveWeight: 1)
            window1 = TestWindow.new(id: 1, parent: $0, adaptiveWeight: 2)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                window2 = TestWindow.new(id: 2, parent: $0, adaptiveWeight: 1)
            }
        }
        _ = window1.focusWindow()

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(window2.hWeight, 1)
        assertEquals(window2.vWeight, 1)
        assertEquals(window1.vWeight, 1)
        assertEquals(window1.hWeight, 1)
    }

    func testCreateImplicitContainer() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("move up").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .v_tiles([
                    .window(2),
                    .h_tiles([.window(1), .window(3)]),
                ]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 0)
    }

    func testStop_onRootNode() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("move --boundaries-action stop left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .h_tiles([.window(1), .window(2), .window(3)]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 0)
    }

    func testStop_onRootNode_withOppositeOrientation() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("move --boundaries-action stop up").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .h_tiles([.window(1), .window(2), .window(3)]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 0)
    }

    func testStop_onRootNode_whenNoBoundary() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("move --boundaries-action stop left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .h_tiles([.window(2), .window(1), .window(3)]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 0)
    }

    func testStop_onInnerNode() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 3, parent: $0)
            }
        }

        let result = await parseCommand("move --boundaries-action stop right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .h_tiles([.window(1), .v_tiles([.window(3)]), .window(2)]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 0)
    }

    func testFail() async {
        let workspace = Workspace.get(byName: name)
        workspace.rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
            TestWindow.new(id: 3, parent: $0)
        }

        let result = await parseCommand("move --boundaries-action fail left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.layoutDescription,
            .workspace([
                .h_tiles([.window(1), .window(2), .window(3)]),
            ]),
        )
        assertEquals(result.exitCode.rawValue, 2)
    }

    func testMoveOut() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            TestWindow.new(id: 1, parent: $0)
            TilingContainer.newVTiles(parent: $0, adaptiveWeight: 1).apply {
                assertEquals(TestWindow.new(id: 2, parent: $0).focusWindow(), true)
                TestWindow.new(id: 3, parent: $0)
                TestWindow.new(id: 4, parent: $0)
            }
        }

        await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            root.layoutDescription,
            .h_tiles([
                .window(1),
                .window(2),
                .v_tiles([
                    .window(3),
                    .window(4),
                ]),
            ]),
        )
    }

    func testMoveOutWithNormalization_right() async {
        config.enableNormalizationFlattenContainers = true

        let workspace = Workspace.get(byName: name).apply {
            TestWindow.new(id: 1, parent: $0.rootTilingContainer)
            assertEquals(TestWindow.new(id: 2, parent: $0.rootTilingContainer).focusWindow(), true)
        }

        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .h_tiles([
                .window(1),
                .window(2),
            ]),
        )
        assertEquals(focus.windowOrNil?.windowId, 2)
    }

    func testMoveOutWithNormalization_left() async {
        config.enableNormalizationFlattenContainers = true

        let workspace = Workspace.get(byName: name).apply {
            assertEquals(TestWindow.new(id: 1, parent: $0.rootTilingContainer).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0.rootTilingContainer)
        }

        await parseCommand("move left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(
            workspace.rootTilingContainer.layoutDescription,
            .h_tiles([
                .window(1),
                .window(2),
            ]),
        )
        assertEquals(focus.windowOrNil?.windowId, 1)
    }

    func testMoveFloatingWindow() async throws {
        let window = TestWindow.new(
            id: 1,
            parent: Workspace.get(byName: name).floatingWindowsContainer,
            rect: Rect(topLeftX: 500, topLeftY: 400, width: 200, height: 100),
        )
        assertEquals(window.focusWindow(), true)

        assertEquals(await parseCommand("move --floating-pixels 50 left").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 450, y: 400))

        assertEquals(await parseCommand("move --floating-pixels 30 down").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 450, y: 430))

        assertEquals(await parseCommand("move --floating-pixels 20 up").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 450, y: 410))

        assertEquals(await parseCommand("move --floating-pixels 10 right").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 460, y: 410))

        assertEquals(try await window.getAxRect(.nonCancellable)?.size, CGSize(width: 200, height: 100))
        assertEquals(Workspace.get(byName: name).floatingWindows.map(\.windowId), [1])
    }

    func testMoveFloatingWindow_defaultPixels() async throws {
        let window = TestWindow.new(
            id: 1,
            parent: Workspace.get(byName: name).floatingWindowsContainer,
            rect: Rect(topLeftX: 500, topLeftY: 400, width: 200, height: 100),
        )
        assertEquals(window.focusWindow(), true)

        // 10% of the 1920x1080 test monitor
        await parseCommand("move right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 692, y: 400))

        await parseCommand("move up").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 692, y: 292))
    }

    func testMoveFloatingWindow_stopAtMonitorEdge() async throws {
        let window = TestWindow.new(
            id: 1,
            parent: Workspace.get(byName: name).floatingWindowsContainer,
            rect: Rect(topLeftX: 1650, topLeftY: 20, width: 200, height: 100),
        )
        assertEquals(window.focusWindow(), true)

        assertEquals(await parseCommand("move --floating-pixels 100 right").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 1720, y: 20))

        assertEquals(await parseCommand("move --floating-pixels 100 right").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 1720, y: 20))

        assertEquals(await parseCommand("move --floating-pixels 100 up").cmdOrDie.run(.defaultEnv, .emptyStdin).exitCode.rawValue, 0)
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 1720, y: 0))
    }

    func testMoveFloatingWindow_windowIsAlreadyBeyondMonitorEdge() async throws {
        let window = TestWindow.new(
            id: 1,
            parent: Workspace.get(byName: name).floatingWindowsContainer,
            rect: Rect(topLeftX: 1800, topLeftY: 400, width: 200, height: 100),
        )
        assertEquals(window.focusWindow(), true)

        // Don't pull the window back
        await parseCommand("move --floating-pixels 50 right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 1800, y: 400))

        await parseCommand("move --floating-pixels 50 left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 1750, y: 400))
    }

    func testMoveFloatingWindow_invisibleWorkspace() async throws {
        let window = TestWindow.new(
            id: 1,
            parent: Workspace.get(byName: "b").floatingWindowsContainer,
            rect: Rect(topLeftX: 500, topLeftY: 400, width: 200, height: 100),
        )
        assertEquals(Workspace.get(byName: "a").focusWorkspace(), true)

        let result = await parseCommand("move --window-id 1 left").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 2)
        assertEquals(result.stderr, ["moving floating windows of invisible workspaces isn't yet supported"])
        assertEquals(try await window.getAxRect(.nonCancellable)?.topLeftCorner, CGPoint(x: 500, y: 400))
    }

    func testFloatingPixels_tilingWindow() async {
        let root = Workspace.get(byName: name).rootTilingContainer.apply {
            assertEquals(TestWindow.new(id: 1, parent: $0).focusWindow(), true)
            TestWindow.new(id: 2, parent: $0)
        }

        let result = await parseCommand("move --floating-pixels 50 right").cmdOrDie.run(.defaultEnv, .emptyStdin)
        assertEquals(result.exitCode.rawValue, 0)
        assertEquals(root.layoutDescription, .h_tiles([.window(2), .window(1)]))
    }
}

extension TreeNode {
    var layoutDescription: LayoutDescription {
        return switch nodeCases {
            case .window(let window): .window(window.windowId)
            case .workspace(let workspace): .workspace(workspace.children.map(\.layoutDescription))
            case .floatingWindowsContainer(let container): .floatingWindowsContainer(container.children.map(\.layoutDescription))
            case .macosMinimizedWindowsContainer: .macosMinimized
            case .macosFullscreenWindowsContainer: .macosFullscreen
            case .macosHiddenAppsWindowsContainer: .macosHiddeAppWindow
            case .macosPopupWindowsContainer: .macosPopupWindowsContainer
            case .tilingContainer(let container):
                switch container.layout {
                    case .tiles:
                        container.orientation == .h
                            ? .h_tiles(container.children.map(\.layoutDescription))
                            : .v_tiles(container.children.map(\.layoutDescription))
                    case .accordion:
                        container.orientation == .h
                            ? .h_accordion(container.children.map(\.layoutDescription))
                            : .v_accordion(container.children.map(\.layoutDescription))
                }
        }
    }
}

enum LayoutDescription: Equatable {
    case workspace([LayoutDescription])
    case h_tiles([LayoutDescription])
    case v_tiles([LayoutDescription])
    case h_accordion([LayoutDescription])
    case v_accordion([LayoutDescription])
    case floatingWindowsContainer([LayoutDescription])
    case window(UInt32)
    case macosPopupWindowsContainer
    case macosMinimized
    case macosHiddeAppWindow
    case macosFullscreen
}
