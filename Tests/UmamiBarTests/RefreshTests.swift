import XCTest
@testable import UmamiBar

private final class FixtureProtocol: URLProtocol {
    static var response: ((URLRequest) -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let (status, data) = Self.response?(request), let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class RefreshTests: XCTestCase {
    private func fixture() throws -> (Preferences, SnapshotStore, Connection, API, SiteSnapshot) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("UmamiBar-refresh-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: directory); FixtureProtocol.response = nil }
        let preferences = Preferences(defaults: UserDefaults(suiteName: "UmamiBar.refresh.\(UUID().uuidString)")!)
        let store = SnapshotStore(directory: directory)
        let connection = Connection(base: URL(string: "http://localhost:12345/api")!, key: "fixture-only")
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [FixtureProtocol.self]
        let api = API(configuration: configuration)
        let end = Date().addingTimeInterval(-3600)
        let stats = try JSONDecoder().decode(Stats.self, from: Data(#"{"visitors":2,"pageviews":4}"#.utf8))
        let record = SiteSnapshot(websiteID: "a", period: 0, timezone: TimeZone.current.identifier, start: Period.day.start(before: end), end: end, savedAt: end, stats: stats, points: [Point(x: "old bucket", y: 2)], previousVisitors: nil)
        try store.save(record, base: connection.base)
        return (preferences, store, connection, api, record)
    }
    func testMenuPreferenceChangePublishesRecoveredCountImmediately() throws {
        let (preferences, store, connection, api, old) = try fixture()
        let controller = MainController(preferences: preferences, snapshots: store, api: api, connectionOverride: connection, selectedSites: [Website(id: "a", name: "A", domain: "a.test")])
        let done = expectation(description: "menu preference propagated")
        controller.onSummary = { summary in
            guard summary.title.isEmpty else { return }
            XCTAssertEqual(summary.count, 2)
            done.fulfill()
        }
        preferences.menuDisplay = .icon
        wait(for: [done], timeout: 2); controller.onSummary = nil
        XCTAssertEqual(store.records(base: connection.base, period: .day)["a"]?.end, old.end)
    }
    func testFailedTrendDoesNotPairNewStatsWithOldChartOrOverwriteDisk() throws {
        let (preferences, store, connection, api, old) = try fixture()
        FixtureProtocol.response = { request in
            if request.url!.path.hasSuffix("/pageviews") { return (500, Data()) }
            return (200, Data(#"{"visitors":9,"pageviews":18}"#.utf8))
        }
        let controller = MainController(preferences: preferences, snapshots: store, api: api, connectionOverride: connection, selectedSites: [Website(id: "a", name: "A", domain: "a.test")])
        let done = expectation(description: "refresh failed but kept matching snapshot")
        controller.onSummary = { [weak controller] summary in
            guard controller?.isRefreshing == false else { return }
            XCTAssertEqual(summary.count, 2)
            done.fulfill()
        }
        controller.refreshIfNeeded()
        wait(for: [done], timeout: 3)
        controller.onSummary = nil
        let stored = try XCTUnwrap(store.records(base: connection.base, period: .day)["a"])
        XCTAssertEqual(stored.end, old.end)
        XCTAssertEqual(stored.stats.visitors, 2)
        XCTAssertEqual(stored.points.first?.x, "old bucket")
    }
    func testSuccessfulRefreshReplacesRecoveredSnapshotWithOneCompleteWindow() throws {
        let (preferences, store, connection, api, old) = try fixture()
        FixtureProtocol.response = { request in
            if request.url!.path.hasSuffix("/pageviews") { return (200, Data(#"{"sessions":[]}"#.utf8)) }
            return (200, Data(#"{"visitors":9,"pageviews":18}"#.utf8))
        }
        let controller = MainController(preferences: preferences, snapshots: store, api: api, connectionOverride: connection, selectedSites: [Website(id: "a", name: "A", domain: "a.test")])
        let done = expectation(description: "complete refresh committed")
        controller.onSummary = { [weak controller] summary in
            guard controller?.isRefreshing == false else { return }
            XCTAssertEqual(summary.count, 9)
            XCTAssertFalse(summary.tooltip.contains("本地数据"))
            done.fulfill()
        }
        controller.refreshIfNeeded()
        wait(for: [done], timeout: 3)
        controller.onSummary = nil
        let stored = try XCTUnwrap(store.records(base: connection.base, period: .day)["a"])
        XCTAssertGreaterThan(stored.end, old.end)
        XCTAssertEqual(stored.stats.visitors, 9)
        XCTAssertEqual(stored.previousVisitors, 9)
        XCTAssertFalse(stored.points.isEmpty)
    }
    func testDisabledPersistenceDoesNotWriteSuccessfulRefresh() throws {
        let (preferences, store, connection, api, old) = try fixture()
        preferences.retainData = false
        FixtureProtocol.response = { request in
            (200, request.url!.path.hasSuffix("/pageviews") ? Data(#"{"sessions":[]}"#.utf8) : Data(#"{"visitors":7}"#.utf8))
        }
        let controller = MainController(preferences: preferences, snapshots: store, api: api, connectionOverride: connection, selectedSites: [Website(id: "a", name: "A", domain: "a.test")])
        let done = expectation(description: "live result without persistence")
        controller.onSummary = { [weak controller] summary in
            guard controller?.isRefreshing == false else { return }
            XCTAssertEqual(summary.count, 7); done.fulfill()
        }
        controller.refreshIfNeeded(); wait(for: [done], timeout: 3); controller.onSummary = nil
        XCTAssertEqual(store.records(base: connection.base, period: .day)["a"]?.end, old.end)
    }
    func testLiveCountsFeedMenuAndFailuresShowUnavailable() throws {
        let (preferences, store, connection, api, _) = try fixture()
        preferences.menuDisplay = .live
        var activeStatus = 200
        FixtureProtocol.response = { request in
            request.url!.path.hasSuffix("/active") ? (activeStatus, Data(#"{"visitors":5}"#.utf8)) : (500, Data())
        }
        let controller = MainController(preferences: preferences, snapshots: store, api: api, connectionOverride: connection, selectedSites: [Website(id: "a", name: "A", domain: "a.test")])
        let loaded = expectation(description: "live count shown")
        controller.onSummary = { summary in if summary.count == 5 { XCTAssertTrue(summary.live); loaded.fulfill() } }
        controller.refreshLive(); wait(for: [loaded], timeout: 3)
        // A recent attempt is not repeated until maxAge passes.
        controller.onSummary = { _ in XCTFail("refreshed too soon") }
        controller.refreshLive(maxAge: 60)
        activeStatus = 500
        let failed = expectation(description: "failed live count is unavailable, not zero")
        controller.onSummary = { summary in if summary.count == nil { XCTAssertFalse(summary.live); failed.fulfill() } }
        controller.refreshLive(maxAge: 0); wait(for: [failed], timeout: 3); controller.onSummary = nil
    }
}
