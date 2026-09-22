@testable import AppBundle
import Common
import XCTest

final class ListAppsTest: XCTestCase {
    func testParse() {
        assertNotNil(parseCommand("list-apps --macos-native-hidden").cmdOrDie)
        assertNotNil(parseCommand("list-apps --macos-native-hidden no").cmdOrDie)
        assertNotNil(parseCommand("list-apps --format %{app-bundle-id}").cmdOrDie)
        assertNotNil(parseCommand("list-apps --count").cmdOrDie)
        assertEquals(parseCommand("list-apps --format %{app-bundle-id} --count").errorOrNil, "ERROR: Conflicting options: --count, --format")
        assertEquals(parseCommand("list-apps --format %{all}").errorOrNil, "%{all} interpolation variable requires --json flag")
        assertNotNil(parseCommand("list-apps --format %{all} --json").cmdOrDie)
    }

    func testFormatAll() {
        assertEquals(
            ListAppsCmdArgs(rawArgs: []).copy(\._format, [.interVar(.plainInterVar(.all))]).format,
            [
                .interVar(.formatVar(.app(.appBundleId))),
                .interVar(.formatVar(.app(.appName))),
                .interVar(.formatVar(.app(.appPid))),
                .interVar(.formatVar(.app(.appExecPath))),
                .interVar(.formatVar(.app(.appBundlePath))),
            ],
        )
    }
}
