import AppKit
import Common

struct ListWindowsCommand: Command {
    let args: ListWindowsCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) async -> BinaryExitCode {
        let focus = focus
        var windows: [Window] = []

        if args.filteringOptions.focused {
            switch focus.windowOrNil {
                case let window?: windows = [window]
                case nil: return .fail(io.err(noWindowIsFocused))
            }
        } else {
            var workspaces: Set<Workspace> = args.filteringOptions.workspaces.isEmpty
                ? Workspace.all.toSet()
                : args.filteringOptions.workspaces
                    .flatMap { filter in
                        switch filter {
                            case .focused: [focus.workspace]
                            case .visible: Workspace.all.filter(\.isVisible)
                            case .name(let name): [Workspace.get(byName: name.raw)]
                        }
                    }
                    .toSet()
            if !args.filteringOptions.monitors.isEmpty {
                let monitors: Set<CGPoint> = args.filteringOptions.monitors.resolveMonitors(io)
                if monitors.isEmpty { return .fail }
                workspaces = workspaces.filter { monitors.contains($0.workspaceMonitor.rect.topLeftCorner) }
            }
            windows = workspaces.flatMap(\.allLeafWindowsRecursive)
            if let pid = args.filteringOptions.pidFilter {
                windows = windows.filter { $0.app.pid == pid }
            }
            if let appId = args.filteringOptions.appIdFilter {
                windows = windows.filter { $0.app.rawAppBundleId == appId }
            }
        }

        if args.outputOnlyCount {
            return .succ(io.out("\(windows.count)"))
        } else {
            let dfsIndices: [UInt32: Int] = args.sortBy.contains(.dfs) && windows.count > 1 ? await getDfsIndices(windows) : [:]
            var _list: [WindowWithPrefetchedTitle] = [] // todo cleanup
            for window in windows {
                guard let window = try? await WindowWithPrefetchedTitle.resolveWindow(
                    window,
                    for: args.format,
                    forceFetchTitle: args.sortBy.contains(.windowTitle),
                    .nonCancellable,
                ) else { return .fail(io.err(bugPrompt())) }
                _list.append(window)
            }
            _list = _list.filter { $0.window.isBound }
            let sortKeys: [WindowSortKey] = (args.sortBy.isEmpty ? [.appName, .windowTitle] : args.sortBy) + [.windowId]
            _list = _list.sortedBy(sortKeys.map { sortKey in
                { (window: WindowWithPrefetchedTitle) -> SortValue in
                    switch sortKey {
                        case .dfs: .int(dfsIndices[window.window.windowId] ?? Int.max)
                        case .pid: .int(Int(window.window.app.pid))
                        case .windowId: .int(Int(window.window.windowId))
                        case .windowTitle: .string(window.title ?? "")
                        case .appName: .string(window.window.app.name ?? "")
                    }
                }
            })

            let list = _list.map { AeroObj.window($0) }
            if args.json {
                return switch list.formatToJson(args.format, ignoreRightPaddingVar: args._format.isEmpty) {
                    case .success(let json): .succ(io.out(json))
                    case .failure(let msg): .fail(io.err(msg))
                }
            } else {
                return switch list.format(args.format) {
                    case .success(let lines): .succ(io.out(lines))
                    case .failure(let msg): .fail(io.err(msg.map(\.description).joinErrors()))
                }
            }
        }
    }
}

private enum SortValue: Comparable {
    case int(Int)
    case string(String)
}

/// Monitors and workspaces are considered to be part of the tree
@MainActor
private func getDfsIndices(_ windows: [Window]) async -> [UInt32: Int] {
    let monitors = sortedMonitorInfos.map(\.rect.topLeftCorner)
    func monitorIndex(_ workspace: Workspace) -> Int { monitors.firstIndex(of: workspace.workspaceMonitor.rect.topLeftCorner) ?? Int.max }
    let workspaces = windows.compactMap(\.nodeWorkspace).toSet().sorted { (monitorIndex($0), $0) < (monitorIndex($1), $1) }
    var result: [UInt32: Int] = [:]
    for workspace in workspaces {
        let dfs = await getDfsWindowsWithFloatingSeenAsTiling(workspace: workspace)
        // Windows that aren't part of the tiling tree (e.g. macOS native fullscreen windows) go after the tiling windows
        for window in dfs + workspace.allLeafWindowsRecursive where result[window.windowId] == nil {
            result[window.windowId] = result.count
        }
    }
    return result
}
