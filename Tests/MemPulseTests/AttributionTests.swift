import XCTest
@testable import MemPulse

final class AttributionTests: XCTestCase {
    func process(_ pid: Int32, _ parent: Int32, _ path: String, start: UInt64 = 10, memory: UInt64? = 100) -> ProcessRecord {
        ProcessRecord(pid: pid, parent: parent, startSeconds: start, startMicroseconds: 0,
                      name: "process", path: path, memory: memory, memoryError: memory == nil ? 13 : 0)
    }
    func groups(_ records: [ProcessRecord]) -> [AppGroup] {
        Attribution.group(records, running: [:]) { AppIdentity(path: $0, name: $0) }
    }
    func testHelpersAndExternalDescendantsAreCountedOnce() {
        let result = groups([
            process(1, 0, "/Applications/Editor.app/Contents/MacOS/editor"),
            process(2, 1, "/Applications/Editor.app/Contents/Helpers/Helper.app/Contents/MacOS/helper"),
            process(3, 2, "/usr/bin/language-server")
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].total, 300)
        XCTAssertEqual(result[0].processes.count, 3)
        XCTAssertEqual(result[0].app.path, "/Applications/Editor.app")
    }
    func testParentOwnershipOverridesChildBundle() {
        let result = groups([
            process(1, 0, "/Applications/A.app/Contents/MacOS/A"),
            process(2, 1, "/Applications/B.app/Contents/MacOS/B"),
            process(3, 2, "/usr/bin/worker")
        ])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result.first?.app.path, "/Applications/A.app")
        XCTAssertEqual(result.first?.total, 300)
    }
    func testReusedParentAndCyclesStayUnassigned() {
        let result = groups([
            process(1, 0, "/Applications/A.app/Contents/MacOS/A", start: 20),
            process(2, 1, "/usr/bin/old", start: 10),
            process(3, 4, "/usr/bin/cycle"), process(4, 3, "/usr/bin/cycle")
        ])
        XCTAssertEqual(result.first { $0.id == "unassigned" }?.processes.count, 3)
    }
    func testUnreadableIsNotZeroAndInstallationsRemainSeparate() {
        let result = groups([
            process(1, 0, "/Applications/A.app/Contents/MacOS/A", memory: nil),
            process(2, 0, "/Users/me/Applications/A.app/Contents/MacOS/A")
        ])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result.first { $0.app.path == "/Applications/A.app" }?.unreadable, 1)
        XCTAssertNil(result.first { $0.app.path == "/Applications/A.app" }?.processes[0].process.memory)
    }
    func testPythonBundleInheritsKiroThroughParentChainRegardlessOfInputOrder() {
        let records = [
            process(86152, 1, "/Applications/Kiro.app/Contents/MacOS/Kiro"),
            process(86575, 86152, "/Applications/Kiro.app/Contents/Frameworks/Helper.app/Contents/MacOS/Helper"),
            process(86668, 86575, "/opt/homebrew/Python.framework/Resources/Python.app/Contents/MacOS/Python"),
            process(86969, 86668, "/opt/homebrew/Python.framework/Resources/Python.app/Contents/MacOS/Python")
        ]
        for input in [records, records.reversed().map { $0 }] {
            let result = groups(input)
            XCTAssertEqual(result.count, 1)
            XCTAssertEqual(result.first?.app.path, "/Applications/Kiro.app")
            XCTAssertEqual(result.first?.total, 400)
        }
    }

    func testBundleFallbackWhenParentMissingOrNewer() {
        let result = groups([
            process(10, 999, "/Applications/A.app/Contents/MacOS/A"),
            process(11, 12, "/Applications/B.app/Contents/MacOS/B", start: 10),
            process(12, 0, "/Applications/C.app/Contents/MacOS/C", start: 20)
        ])
        XCTAssertEqual(Set(result.map { $0.app.path }), Set(["/Applications/A.app", "/Applications/B.app", "/Applications/C.app"]))
    }

    func testBundleBoundary() {
        XCTAssertNil(Attribution.outerBundle("/tmp/fake.application/bin"))
        XCTAssertNil(Attribution.outerBundle("relative.app/bin"))
    }
    func testSystemXPCIsNotAnAppEvenWhenWorkspaceListsIt() {
        let path = "/System/Library/Frameworks/WebKit.framework/XPCServices/WebContent.xpc"
        let record = process(10, 1, path + "/Contents/MacOS/WebContent")
        let result = Attribution.group([record], running: [10: AppIdentity(path: path, name: "Safari WebContent")]) {
            AppIdentity(path: $0, name: $0)
        }
        XCTAssertEqual(result.first?.id, "unassigned")
    }
}
