import AppKit
import Common

struct FocusCommand: Command {
    let args: FocusCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        if let window = target.windowOrNil, await shouldFailBecauseFullscreen_nonCancellable(
            window: window,
            failIfFullscreen: args.failIfFullscreen,
            failIfMacosNativeFullscreen: args.failIfMacosNativeFullscreen,
        ) {
            return .fail
        }
        // todo bug: floating windows break mru
        let floatingWindows = args.floatingAsTiling ? await makeFloatingWindowsSeenAsTiling(workspace: target.workspace) : []
        defer {
            if args.floatingAsTiling {
                restoreFloatingWindows(floatingWindows: floatingWindows, workspace: target.workspace)
            }
        }

        switch args.target {
            case .direction(let direction):
                let window = target.windowOrNil
                if let (parent, ownIndex) = window?.closestParent(hasChildrenInDirection: direction, withLayout: nil) {
                    guard let windowToFocus = parent.children[ownIndex + direction.focusOffset]
                        .findLeafWindowRecursive(snappedTo: direction.opposite) else { return .fail(io.err(bugPrompt())) }
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return hitWorkspaceBoundaries(target, io, args, direction)
                }
            case .windowId(let windowId):
                if let windowToFocus = Window.get(byId: windowId) {
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return .fail(io.err("Can't find window with ID \(windowId)"))
                }
            case .dfsIndex(let dfsIndex):
                if let windowToFocus = target.workspace.rootTilingContainer.allLeafWindowsRecursive.getOrNil(atIndex: Int(dfsIndex)) {
                    return .from(bool: windowToFocus.focusWindow())
                } else {
                    return .fail(io.err("Can't find window with DFS index \(dfsIndex)"))
                }
            case .dfsRelative(let nextPrev):
                let windows = target.workspace.rootTilingContainer.allLeafWindowsRecursive
                guard let currentIndex = windows.firstIndex(where: { $0 == target.windowOrNil }) else {
                    return .fail
                }
                var targetIndex = switch nextPrev {
                    case .dfsNext: currentIndex + 1
                    case .dfsPrev: currentIndex - 1
                }
                if !(0 ..< windows.count).contains(targetIndex) {
                    switch args.boundariesAction {
                        case .stop: return .succ
                        case .fail: return .fail
                        case .wrapAroundTheWorkspace: targetIndex = (targetIndex + windows.count) % windows.count
                        case .wrapAroundAllMonitors: return .fail(io.err(bugPrompt("Must be discarded by args parser")))
                    }
                }
                return .from(bool: windows[targetIndex].focusWindow())
        }
    }
}

@MainActor private func hitWorkspaceBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
) -> BinaryExitCode {
    switch args.boundaries {
        case .workspace:
            return switch args.boundariesAction {
                case .stop: .succ
                case .fail: .fail
                case .wrapAroundTheWorkspace: wrapAroundTheWorkspace(target, io, direction)
                case .wrapAroundAllMonitors: .fail(io.err("Must be discarded by args parser"))
            }
        case .allMonitorsOuterFrame:
            let currentMonitor = target.workspace.workspaceMonitor
            guard let (monitors, index) = currentMonitor.findRelativeMonitor(inDirection: direction) else {
                return .fail(io.err(bugPrompt("Should never happen. Can't find the current monitor")))
            }

            if let targetMonitor = monitors.getOrNil(atIndex: index) {
                return .from(bool: targetMonitor.activeWorkspace.focusWorkspace())
            } else {
                guard let wrapped = monitors.get(wrappingIndex: index) else { return .fail(io.err(bugPrompt("\(index) \(monitors)"))) }
                return hitAllMonitorsOuterFrameBoundaries(target, io, args, direction, wrapped)
            }
    }
}

@MainActor private func hitAllMonitorsOuterFrameBoundaries(
    _ target: LiveFocus,
    _ io: CmdIo,
    _ args: FocusCmdArgs,
    _ direction: CardinalDirection,
    _ wrappedMonitor: MonitorInfo,
) -> BinaryExitCode {
    switch args.boundariesAction {
        case .stop:
            return .succ
        case .fail:
            return .fail
        case .wrapAroundTheWorkspace:
            return wrapAroundTheWorkspace(target, io, direction)
        case .wrapAroundAllMonitors:
            wrappedMonitor.activeWorkspace.findLeafWindowRecursive(snappedTo: direction.opposite)?.markAsMostRecentChild()
            return .from(bool: wrappedMonitor.activeWorkspace.focusWorkspace())
    }
}

@MainActor private func wrapAroundTheWorkspace(_ target: LiveFocus, _ io: CmdIo, _ direction: CardinalDirection) -> BinaryExitCode {
    guard let windowToFocus = target.workspace.findLeafWindowRecursive(snappedTo: direction.opposite) else {
        return .fail(io.err(noWindowIsFocused))
    }
    return .from(bool: windowToFocus.focusWindow())
}

@MainActor private func makeFloatingWindowsSeenAsTiling(workspace: Workspace) async -> [FloatingWindowData] {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    var _floatingWindows: [FloatingWindowData] = []
    for window in workspace.floatingWindows {
        guard let position = await getPositionInTilingTree(floatingWindow: window, workspace: workspace) else { continue }

        let data = window.unbindFromParent()
        _floatingWindows.append(FloatingWindowData(window: window, position: position, adaptiveWeight: data.adaptiveWeight))
    }
    let floatingWindows = floatingWindowsInsertionOrder(_floatingWindows) { $0.position }

    for floating in floatingWindows { // Make floating windows be seen as tiling
        floating.window.bind(to: floating.position.tilingParent, adaptiveWeight: 1, index: floating.position.index)
    }
    return floatingWindows
}

/// The same as `rootTilingContainer.allLeafWindowsRecursive` after `makeFloatingWindowsSeenAsTiling`, but without mutating the tree
@MainActor func getDfsWindowsWithFloatingSeenAsTiling(workspace: Workspace) async -> [Window] {
    var floatingWindows: [(window: Window, position: PositionInTilingTree)] = []
    for window in workspace.floatingWindows {
        guard let position = await getPositionInTilingTree(floatingWindow: window, workspace: workspace) else { continue }
        floatingWindows.append((window, position))
    }
    var virtualChildren: [ObjectIdentifier: [TreeNode]] = [:]
    for (window, position) in floatingWindowsInsertionOrder(floatingWindows, { $0.position }) {
        // The tree could have changed while we were awaiting AX
        guard window.parent === workspace.floatingWindowsContainer else { continue }
        var children = virtualChildren[ObjectIdentifier(position.tilingParent)] ?? position.tilingParent.children
        children.insert(window, at: min(position.index, children.count))
        virtualChildren[ObjectIdentifier(position.tilingParent)] = children
    }
    var result: [Window] = []
    func visit(_ node: TreeNode) {
        if let window = node as? Window {
            result.append(window)
        }
        for child in virtualChildren[ObjectIdentifier(node)] ?? node.children {
            visit(child)
        }
    }
    visit(workspace.rootTilingContainer)
    return result
}

/// The order in which floating windows are inserted into the tiling tree
@MainActor private func floatingWindowsInsertionOrder<T>(_ floatingWindows: [T], _ position: (T) -> PositionInTilingTree) -> [T] {
    floatingWindows.sortedBy { position($0).center.getProjection(position($0).tilingParent.orientation) }.reversed()
}

/// The floating window parent container is determined as the smallest tiling container that contains the center of the floating window
@MainActor private func getPositionInTilingTree(floatingWindow window: Window, workspace: Workspace) async -> PositionInTilingTree? {
    // todo bug: we shouldn't access ax api here. What if the window was moved but it wasn't committed to ax yet?
    guard let center = try? await window.getCenterAsIfUnhiddenFromCorner(.nonCancellable) else { return nil }

    let tilingParent: TilingContainer
    let index: Int
    if let target = center.coerce(in: workspace.workspaceMonitor.visibleRectPaddedByOuterGaps)?
        .findWindowRecursively(in: workspace.rootTilingContainer, virtual: true, fullscreenCoversAll: false)
    {
        guard let targetCenter = try? await target.getCenterAsIfUnhiddenFromCorner(.nonCancellable) else { return nil }
        guard let _tilingParent = target.parent as? TilingContainer else { return nil }
        tilingParent = _tilingParent
        index = switch tilingParent.layout {
            case .tiles:
                center.getProjection(tilingParent.orientation) >= targetCenter.getProjection(tilingParent.orientation)
                    ? target.ownIndex.orDie() + 1
                    : target.ownIndex.orDie()
            case .accordion:
                center.getProjection(tilingParent.orientation) >= targetCenter.getProjection(tilingParent.orientation)
                    ? tilingParent.children.count
                    : 0
        }
    } else {
        index = 0
        tilingParent = workspace.rootTilingContainer
    }
    return PositionInTilingTree(center: center, tilingParent: tilingParent, index: index)
}

@MainActor private func restoreFloatingWindows(floatingWindows: [FloatingWindowData], workspace: Workspace) {
    let mruBefore = workspace.mostRecentWindowRecursive
    defer {
        mruBefore?.markAsMostRecentChild()
    }
    for floating in floatingWindows {
        floating.window.bind(to: workspace.floatingWindowsContainer, adaptiveWeight: floating.adaptiveWeight, index: INDEX_BIND_LAST)
    }
}

private struct PositionInTilingTree {
    let center: CGPoint
    let tilingParent: TilingContainer
    let index: Int
}

private struct FloatingWindowData {
    let window: Window
    let position: PositionInTilingTree
    let adaptiveWeight: CGFloat
}

extension TreeNode {
    @MainActor
    func findLeafWindowRecursive(snappedTo direction: CardinalDirection) -> Window? {
        switch nodeCases {
            case .workspace(let workspace):
                return workspace.rootTilingContainer.findLeafWindowRecursive(snappedTo: direction)
            case .window(let window):
                return window
            case .tilingContainer(let container):
                if direction.orientation == container.orientation {
                    return (direction.isPositive ? container.children.last : container.children.first)?
                        .findLeafWindowRecursive(snappedTo: direction)
                } else {
                    return mostRecentChild?.findLeafWindowRecursive(snappedTo: direction)
                }
            case .macosMinimizedWindowsContainer, .macosFullscreenWindowsContainer,
                 .macosPopupWindowsContainer, .macosHiddenAppsWindowsContainer,
                 .floatingWindowsContainer:
                die("Impossible")
        }
    }
}
