import AppKit
import Common
import Foundation

struct BalanceSizesCommand: Command {
    let args: BalanceSizesCmdArgs
    /*conforms*/ let shouldResetClosedWindowsCache = false

    func run(_ env: CmdEnv, _ io: CmdIo) -> BinaryExitCode {
        guard let target = args.resolveTargetOrReportError(env, io) else { return .fail }
        balance(target.workspace.rootTilingContainer)
        return .succ
    }
}

@MainActor
private func balance(_ parent: TilingContainer) {
    // Spread the weight the container already has instead of resetting the weights to a constant. Weights are
    // converted into real sizes only by the layout pass, which runs once the whole command list is over. That's why
    // the commands that follow balance-sizes in the same list (e.g. resize) must observe the same weight scale as if
    // balance-sizes was invoked on its own https://github.com/nikitabobko/AeroSpace/issues/1837
    let children = parent.children
    let balancedWeight: CGFloat? = switch parent.layout {
        case .tiles: CGFloat(children.sumOfDouble { $0.getWeight(parent.orientation) }).div(children.count)
        case .accordion: nil // Do nothing
    }
    for child in children {
        if let balancedWeight {
            child.setWeight(parent.orientation, balancedWeight)
        }
        if let child = child as? TilingContainer {
            balance(child)
        }
    }
}
