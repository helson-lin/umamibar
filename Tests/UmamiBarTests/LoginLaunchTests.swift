import XCTest
import ServiceManagement
@testable import UmamiBar

final class LoginLaunchTests: XCTestCase {
    func testMissingServiceRecordAllowsFirstRegistration() throws {
        guard #available(macOS 13.0, *) else { throw XCTSkip("SMAppService requires macOS 13") }
        XCTAssertEqual(LoginLaunch.registrationStatus(.notFound), .off)
        XCTAssertEqual(LoginLaunch.registrationStatus(.notRegistered), .off)
    }

    func testRegisteredAndApprovalStatesRemainDistinct() throws {
        guard #available(macOS 13.0, *) else { throw XCTSkip("SMAppService requires macOS 13") }
        XCTAssertEqual(LoginLaunch.registrationStatus(.enabled), .enabled)
        XCTAssertEqual(LoginLaunch.registrationStatus(.requiresApproval), .requiresApproval)
    }

    func testUnbundledExecutableCannotChangeLoginItems() {
        let login = LoginLaunch(bundleURL: URL(fileURLWithPath: "/tmp/umamibar-command-line"))
        XCTAssertEqual(login.status, .unavailable)
        XCTAssertThrowsError(try login.setEnabled(true))
    }
}
