import XCTest
@testable import UmamiBar

final class PreferencesTests: XCTestCase {
    private let sites = [Website(id: "a", name: "Alpha", domain: "a.test"), Website(id: "b", name: "Beta", domain: "b.test"), Website(id: "c", name: "Gamma", domain: "c.test")]
    private func preferences() -> Preferences {
        let defaults = UserDefaults(suiteName: "UmamiBar.tests.\(UUID().uuidString)")!
        return Preferences(defaults: defaults)
    }
    private func snapshot(_ id: String, count: Int = 3, period: Period = .day, end: Date = Date(timeIntervalSince1970: 1_800_000_000), timezone: String = TimeZone.current.identifier) throws -> SiteSnapshot {
        let stats = try JSONDecoder().decode(Stats.self, from: Data("{\"visitors\":\(count),\"pageviews\":12,\"visits\":8,\"bounces\":2,\"totaltime\":90}".utf8))
        return SiteSnapshot(websiteID: id, period: period.rawValue, timezone: timezone, start: period.start(before: end), end: end, savedAt: end.addingTimeInterval(1), stats: stats, points: [Point(x: "bucket", y: 3)], previousVisitors: 2)
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("UmamiBar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
    func testPinOrderNeverChangesOrdinaryOrder() {
        var layout = WebsiteLayout(order: ["a", "b", "c"], pinned: [])
        layout.togglePin("a"); layout.togglePin("c")
        XCTAssertTrue(layout.move("c", by: -1, selected: Set(["a", "b", "c"])))
        XCTAssertEqual(layout.sorted(sites).map(\.id), ["c", "a", "b"])
        layout.togglePin("a")
        XCTAssertEqual(layout.sorted(sites).map(\.id), ["c", "a", "b"])
        layout.togglePin("c")
        XCTAssertEqual(layout.sorted(sites).map(\.id), ["a", "b", "c"])
    }
    func testMoveSkipsUnselectedAndRejectsCrossGroupDrops() {
        var layout = WebsiteLayout(order: ["a", "hidden", "b", "c"], pinned: ["c"])
        XCTAssertTrue(layout.move("b", by: -1, selected: Set(["a", "b", "c"])))
        XCTAssertEqual(layout.sorted(sites).map(\.id), ["c", "b", "a"])
        XCTAssertFalse(layout.place("a", relativeTo: "c", after: false, selected: Set(["a", "b", "c"])))
        XCTAssertFalse(layout.move("b", by: -1, selected: Set(["a", "b", "c"])))
    }
    func testLayoutReconciliationAndConnectionIsolation() {
        let prefs = preferences(), first = URL(string: "https://one.test/api")!, second = URL(string: "https://two.test/api")!
        var layout = WebsiteLayout(order: ["b", "b", "deleted", "a"], pinned: ["a", "a", "deleted"])
        layout.reconcile(["a", "b", "c"])
        XCTAssertEqual(layout.order, ["b", "a", "c"])
        XCTAssertEqual(layout.pinned, ["a"])
        prefs.setLayout(layout, for: first)
        XCTAssertEqual(prefs.layout(for: first, available: ["a", "b", "c"]), layout)
        XCTAssertEqual(prefs.layout(for: second, available: ["a", "b", "c"]).order, ["a", "b", "c"])
    }
    func testMenuPreferencesPersistAndInvalidSourceFallsBack() {
        let prefs = preferences()
        XCTAssertTrue(prefs.retainData)
        XCTAssertEqual(prefs.menuDisplay, .total)
        prefs.menuWebsiteID = "b"; prefs.menuDisplay = .website; prefs.retainData = false
        let reopened = Preferences(defaults: prefs.defaults)
        XCTAssertFalse(reopened.retainData)
        XCTAssertFalse(reopened.reconcileMenuSource(selected: ["a", "b"]))
        XCTAssertTrue(reopened.reconcileMenuSource(selected: ["a"]))
        XCTAssertEqual(reopened.menuDisplay, .total)
        XCTAssertNil(reopened.menuWebsiteID)
    }
    func testMenuSummaryNeverAddsDifferentQueryWindows() throws {
        let a = try snapshot("a"), b = try snapshot("b", end: a.end.addingTimeInterval(60))
        let summary = MenuSummary.make(mode: .total, websiteID: nil, sites: Array(sites.prefix(2)), records: ["a": a, "b": b], period: .day, stale: ["a"])
        XCTAssertNil(summary.count)
        XCTAssertEqual(summary.title, " —")
        let single = MenuSummary.make(mode: .website, websiteID: "a", sites: sites, records: ["a": a], period: .day, stale: ["a"])
        XCTAssertEqual(single.count, 3)
        XCTAssertTrue(single.cached)
        XCTAssertTrue(single.tooltip.contains("Alpha"))
        XCTAssertTrue(single.tooltip.contains("本地数据"))
    }
    func testZeroMissingAndIconRemainDistinct() throws {
        let zero = try snapshot("a", count: 0)
        let values = ["a": zero]
        XCTAssertEqual(MenuSummary.make(mode: .total, websiteID: nil, sites: [sites[0]], records: values, period: .day, stale: []).title, " 0")
        XCTAssertEqual(MenuSummary.make(mode: .total, websiteID: nil, sites: sites, records: values, period: .day, stale: []).title, " —")
        XCTAssertEqual(MenuSummary.make(mode: .icon, websiteID: nil, sites: sites, records: values, period: .day, stale: []).title, "")
        XCTAssertEqual(MenuSummary.make(mode: .total, websiteID: nil, sites: [], records: values, period: .day, stale: []).title, "")
        XCTAssertEqual(MenuSummary.compact(10_000), "10.0K")
    }
    func testSnapshotRoundTripKeepsExactWindowAndScopes() throws {
        let directory = try directory(), store = SnapshotStore(directory: directory)
        let first = URL(string: "https://one.test/api")!, second = URL(string: "https://two.test/api")!
        let value = try snapshot("a")
        try store.save(value, base: first)
        let reopened = SnapshotStore(directory: directory)
        let restored = try XCTUnwrap(reopened.records(base: first, period: .day)["a"])
        XCTAssertEqual(restored.end, value.end)
        XCTAssertEqual(restored.start, value.start)
        XCTAssertEqual(restored.stats.pageviews, 12)
        XCTAssertEqual(restored.points.first?.y, 3)
        XCTAssertTrue(reopened.records(base: second, period: .day).isEmpty)
        XCTAssertTrue(reopened.records(base: first, period: .week).isEmpty)
        XCTAssertTrue(reopened.records(base: first, period: .day, timezone: "A-different-zone").isEmpty)
        let raw = try String(contentsOf: directory.appendingPathComponent("successful-data.json"))
        XCTAssertFalse(raw.contains("Authorization"))
        XCTAssertFalse(raw.contains("api-key"))
    }
    func testDetailCacheRequiresExactDimensionAndWindow() throws {
        let store = SnapshotStore(directory: try directory()), base = URL(string: "https://one.test/api")!
        let value = try snapshot("a")
        try store.save(value, base: base)
        try store.saveDetail(DetailSnapshot(websiteID: "a", period: 0, dimension: "path", end: value.end, rows: [MetricRow(x: "/", y: 2)]), base: base)
        XCTAssertEqual(store.detail(base: base, websiteID: "a", period: .day, dimension: .pages, end: value.end)?.first?.y, 2)
        XCTAssertNil(store.detail(base: base, websiteID: "a", period: .day, dimension: .sources, end: value.end))
        let next = try snapshot("a", end: value.end.addingTimeInterval(60))
        try store.save(next, base: base)
        XCTAssertNil(store.detail(base: base, websiteID: "a", period: .day, dimension: .pages, end: value.end))
    }
    func testClearIsScopedAndFailedWritesDoNotBecomeSuccessfulData() throws {
        let directory = try directory(), base = URL(string: "https://one.test/api")!, other = URL(string: "https://two.test/api")!
        let store = SnapshotStore(directory: directory)
        try store.save(snapshot("a"), base: base); try store.save(snapshot("b"), base: other)
        try store.clear(base: base)
        XCTAssertTrue(store.records(base: base, period: .day).isEmpty)
        XCTAssertEqual(store.records(base: other, period: .day).count, 1)
        try store.clear(); XCTAssertTrue(SnapshotStore(directory: directory).records(base: other, period: .day).isEmpty)
        let blocker = directory.appendingPathComponent("not-a-directory")
        try Data("blocked".utf8).write(to: blocker)
        let invalid = SnapshotStore(directory: blocker)
        XCTAssertThrowsError(try invalid.save(snapshot("a"), base: base))
        XCTAssertTrue(invalid.records(base: base, period: .day).isEmpty)
        XCTAssertNotNil(invalid.lastError)
    }
    func testCorruptSnapshotCanRecoverFromFreshSuccess() throws {
        let directory = try directory(), base = URL(string: "https://one.test/api")!
        try Data("not-json".utf8).write(to: directory.appendingPathComponent("successful-data.json"))
        let store = SnapshotStore(directory: directory)
        XCTAssertNotNil(store.lastError)
        XCTAssertTrue(store.records(base: base, period: .day).isEmpty)
        try store.save(snapshot("a"), base: base)
        XCTAssertNil(store.lastError)
        XCTAssertEqual(SnapshotStore(directory: directory).records(base: base, period: .day).count, 1)
    }
}
