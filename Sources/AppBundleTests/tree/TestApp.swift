@testable import AppBundle
import Common

final class TestApp: AbstractApp {
    let pid: Int32
    let rawAppBundleId: String?
    let name: String?
    let execPath: String? = nil
    let bundlePath: String? = nil
    @MainActor
    static let shared = TestApp()

    private init() {
        self.pid = 0
        self.rawAppBundleId = "bobko.AeroSpace.test-app"
        self.name = rawAppBundleId
    }

    /// An app other than ``shared``. `pid` must be unique among the apps of the test
    init(pid: Int32, name: String) {
        check(pid != 0, "pid 0 is reserved for TestApp.shared")
        self.pid = pid
        self.rawAppBundleId = "bobko.AeroSpace.test-app.\(name)"
        self.name = name
    }

    var _windows: [Window] = []
    var windows: [Window] {
        get { _windows }
        set {
            if let focusedWindow {
                check(newValue.contains(focusedWindow))
            }
            _windows = newValue
        }
    }

    private var _focusedWindow: Window? = nil
    var focusedWindow: Window? {
        get { _focusedWindow }
        set {
            if let window = newValue {
                check(windows.contains(window))
            }
            _focusedWindow = newValue
        }
    }
    @MainActor func getFocusedWindow(_ cm: CancellationMode) -> Window? { _focusedWindow }
}
