@testable import AppBundle
import AppKit

final class TestWindow: Window, CustomStringConvertible {
    private var _rect: Rect?
    private var rectBeforeHidingInCorner: Rect? = nil
    var isMacosFullscreenForTest = false

    @MainActor
    private init(_ id: UInt32, _ app: TestApp, _ parent: NonLeafTreeNodeObject, _ adaptiveWeight: CGFloat, _ rect: Rect?) {
        _rect = rect
        super.init(id: id, app, lastFloatingSize: nil, parent: parent, adaptiveWeight: adaptiveWeight, index: INDEX_BIND_LAST)
    }

    @discardableResult
    @MainActor
    static func new(id: UInt32, parent: NonLeafTreeNodeObject, adaptiveWeight: CGFloat = 1, rect: Rect? = nil, app: TestApp? = nil) -> TestWindow {
        let app = app ?? TestApp.shared
        let wi = TestWindow(id, app, parent, adaptiveWeight, rect)
        app._windows.append(wi)
        return wi
    }

    nonisolated var description: String { "TestWindow(\(windowId))" }

    private var testApp: TestApp { app as! TestApp }

    @MainActor
    override func nativeFocus() {
        appForTests = testApp
        testApp.focusedWindow = self
    }

    /// Simulates `MacWindow.hideInCorner`: the window is moved to the bottom right corner of the monitor, the size is preserved
    @MainActor
    func hideInCornerForTest() {
        guard let rect = _rect, !isHiddenInCorner, let monitorRect = nodeMonitor?.visibleRect else { return }
        rectBeforeHidingInCorner = rect
        _rect = Rect(topLeftX: monitorRect.maxX - 1, topLeftY: monitorRect.maxY - 1, width: rect.width, height: rect.height)
    }

    /// Simulates `MacWindow.unhideFromCorner` followed by the layout
    @MainActor
    func unhideFromCornerForTest() {
        guard let rectBeforeHidingInCorner else { return }
        _rect = rectBeforeHidingInCorner
        self.rectBeforeHidingInCorner = nil
    }

    override var isHiddenInCorner: Bool { rectBeforeHidingInCorner != nil }

    @MainActor override func getFloatingRectAfterUnhidingFromCorner() -> Rect? { rectBeforeHidingInCorner }

    override func closeAxWindow() {
        unbindFromParent()
    }

    override func getTitle(_ cm: CancellationMode) async throws -> String { description }

    @MainActor override func getAxRect(_ cm: CancellationMode) async throws -> Rect? { // todo change to not Optional
        _rect
    }

    @MainActor override func getAxSize(_ cm: CancellationMode) async throws -> CGSize? {
        _rect.map { CGSize(width: $0.width, height: $0.height) }
    }

    override func isMacosFullscreen(_ cm: CancellationMode) async throws -> Bool { isMacosFullscreenForTest }
}
