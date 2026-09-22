@testable import AppBundle
import Common
import XCTest

final class ListMonitorsTest: XCTestCase {
    func testParseListMonitorsCommand() {
        testParseSingleCommandSucc("list-monitors", ListMonitorsCmdArgs(rawArgs: []))
        testParseSingleCommandSucc("list-monitors --focused", ListMonitorsCmdArgs(rawArgs: []).copy(\.focused, true))
        testParseSingleCommandSucc("list-monitors --count", ListMonitorsCmdArgs(rawArgs: []).copy(\.outputOnlyCount, true))
        assertEquals(parseCommand("list-monitors --format %{monitor-id} --count").errorOrNil, "ERROR: Conflicting options: --count, --format")
        assertEquals(parseCommand("list-monitors --format %{all}").errorOrNil, "%{all} interpolation variable requires --json flag")
        testParseSingleCommandSucc(
            "list-monitors --format %{all} --json",
            ListMonitorsCmdArgs(rawArgs: []).copy(\._format, [.interVar(.plainInterVar(.all))]).copy(\.json, true),
        )
    }

    func testFormatAll() {
        assertEquals(
            ListMonitorsCmdArgs(rawArgs: [])
                .copy(\._format, [.interVar(.formatVar(.monitor(.monitorName))), .literal(" "), .interVar(.plainInterVar(.all))])
                .format,
            [
                .interVar(.formatVar(.monitor(.monitorName))),
                .literal(" "),
                .interVar(.formatVar(.monitor(.monitorId_oneBased))),
                .interVar(.formatVar(.monitor(.monitorAppKitNsScreenScreensId))),
                .interVar(.formatVar(.monitor(.monitorName))),
                .interVar(.formatVar(.monitor(.monitorIsMain))),
            ],
        )
    }
}
