import XCTest
@testable import UmamiBar

final class CoreTests: XCTestCase {
    func testDetailDimensionsAndMissingLabels() throws {
        XCTAssertEqual(DetailDimension.options(for: "utm").map(\.rawValue), ["utmSource", "utmMedium", "utmCampaign", "utmTerm", "utmContent"])
        XCTAssertEqual(DetailDimension.options(for: "location").map(\.rawValue), ["country", "region", "city"])
        XCTAssertTrue(DetailDimension.options(for: "invalid").isEmpty)
        for dimension in DetailDimension.allCases {
            for json in [#"{"x":null,"y":3}"#, #"{"x":"","y":3}"#, #"{"y":3}"#] {
                let row = try JSONDecoder().decode(MetricRow.self, from: Data(json.utf8))
                XCTAssertFalse(dimension.label(for: row.x).isEmpty)
                XCTAssertEqual(row.y, 3)
            }
        }
        XCTAssertEqual(DetailDimension.utmCampaign.label(for: nil), L("未设置"))
        XCTAssertEqual(DetailDimension.city.label(for: "  "), L("未知位置"))
        XCTAssertEqual(DetailDimension.sources.label(for: nil), L("直接访问"))
        XCTAssertEqual(DetailDimension.options(for: "events"), [.events])
        XCTAssertEqual(DetailDimension.events.label(for: nil), L("未命名事件"))
        XCTAssertEqual(DetailDimension.country.label(for: "US", locale: Locale(identifier: "en_US")), "United States")
        XCTAssertEqual(DetailDimension.city.label(for: "San Francisco"), "San Francisco")
    }

    func testConnectionNormalization() throws {
        XCTAssertEqual(try Connection.baseURL("https://api.umami.is").absoluteString, "https://api.umami.is/v1")
        XCTAssertEqual(try Connection.baseURL("https://stats.example.com").path, "/api")
        XCTAssertEqual(try Connection.baseURL("https://example.com/analytics/api/").path, "/analytics/api")
        XCTAssertNoThrow(try Connection.baseURL("http://localhost:3000"))
        for input in ["http://example.com", "https://user:secret@example.com", "https://example.com?key=secret", "file:///tmp", "https://example.com#key"] {
            XCTAssertThrowsError(try Connection.baseURL(input))
        }
    }
    func testStatisticsVersions() throws {
        for json in [#"{"visitors":42}"#, #"{"visitors":{"value":42}}"#] {
            XCTAssertEqual(try JSONDecoder().decode(Stats.self, from: Data(json.utf8)).visitors, 42)
        }
        XCTAssertThrowsError(try JSONDecoder().decode(Stats.self, from: Data(#"{"pageviews":42}"#.utf8)))
    }
    func testRollingMonthClampsToLeapDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.date(from: DateComponents(year: 2024, month: 3, day: 31, hour: 12))!
        let start = Period.month.start(before: end, calendar: calendar)
        XCTAssertEqual(calendar.component(.month, from: start), 2)
        XCTAssertEqual(calendar.component(.day, from: start), 29)
        XCTAssertEqual(end.timeIntervalSince(Period.day.start(before: end)), 86400)
    }

    func testSparseSeriesPreservesHourlyPosition() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 16, minute: 28))!
        let buckets = try TimeBuckets.expand([Point(x: "2026-10-15 12:00:00", y: 1)], period: .day, end: end, calendar: calendar)
        XCTAssertEqual(buckets.count, 25) // partial hour on each end
        XCTAssertEqual(buckets.filter { $0.y > 0 }.count, 1)
        XCTAssertEqual(buckets[20].y, 1)
        XCTAssertEqual(buckets.first?.y, 0)
        XCTAssertEqual(buckets.last?.y, 0)
        let iso = try TimeBuckets.expand([Point(x: "2026-10-15T04:00:00.000Z", y: 1)], period: .day, end: end, calendar: calendar)
        XCTAssertEqual(iso.map(\.y), buckets.map(\.y))
    }
    func testEmptySeriesAndDailyBoundary() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15))!
        let buckets = try TimeBuckets.expand([], period: .week, end: end, calendar: calendar)
        XCTAssertEqual(buckets.count, 7)
        XCTAssertTrue(buckets.allSatisfy { $0.y == 0 })
        XCTAssertThrowsError(try TimeBuckets.expand([Point(x: "invalid", y: 1)], period: .day, end: end, calendar: calendar))
    }

    func testUmamiTimezoneGroupedZLabels() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 17, minute: 29))!
        let points = [Point(x: "2026-10-15T16:00:00Z", y: 1), Point(x: "2026-10-15T17:00:00Z", y: 1)]
        let buckets = try TimeBuckets.expand(points, period: .day, end: end, calendar: calendar, wallClockLabels: true)
        XCTAssertEqual(buckets.reduce(0) { $0 + $1.y }, 2)
        XCTAssertEqual(buckets[buckets.count - 2].y, 1)
        XCTAssertEqual(buckets.last?.y, 1)
        XCTAssertThrowsError(try TimeBuckets.expand(points, period: .day, end: end, calendar: calendar))
    }

    func testExpandedStatsAndMissingValues() throws {
        let stats = try JSONDecoder().decode(Stats.self, from: Data(#"{"visitors":8,"pageviews":20,"visits":10,"bounces":4,"totaltime":360}"#.utf8))
        XCTAssertEqual(stats.pageviews, 20)
        XCTAssertEqual(stats.bounceText, "40%")
        XCTAssertEqual(stats.durationText, "1分0秒")
        let missing = try JSONDecoder().decode(Stats.self, from: Data(#"{"visitors":1}"#.utf8))
        XCTAssertEqual(missing.bounceText, "—")
        XCTAssertEqual(missing.durationText, "—")
        let legacy = try JSONDecoder().decode(Stats.self, from: Data(#"{"visitors":{"value":8},"pageviews":{"value":20},"visits":{"value":10},"bounces":{"value":4},"totaltime":{"value":360}}"#.utf8))
        XCTAssertEqual(legacy.durationText, stats.durationText)
        XCTAssertEqual(Stats.change(current: 1, previous: 0), "新增 · 上期为 0")
        XCTAssertEqual(Stats.change(current: 0, previous: 0), "— 持平")
        XCTAssertEqual(Stats.change(current: 10, previous: 20), "↓ 50.0% 较上期")
        let rows = try JSONDecoder().decode([MetricRow].self, from: Data(#"[{"x":null,"y":3},{"x":"/","y":5}]"#.utf8))
        XCTAssertNil(rows[0].x)
        XCTAssertEqual(rows[1].y, 5)
    }

    func testOnlyBlockingErrorsPauseRefresh() {
        XCTAssertTrue(ServiceError.blocking("API Key 无效").pausesRefresh)
        XCTAssertFalse(ServiceError.message("API Key 没有访问权限。").pausesRefresh)
        XCTAssertEqual(ServiceError.blocking("限流").localizedDescription, "限流")
    }

    func testSiteColorsKeepChoicesAndFillGaps() {
        // New sites get distinct colors in order.
        XCTAssertEqual(SiteColors.fill(["a", "b", "c"], saved: [:], count: 8), ["a": 0, "b": 1, "c": 2])
        // Saved choices win; gaps take the first free color; unknown IDs and out-of-range values are dropped.
        XCTAssertEqual(SiteColors.fill(["a", "b", "c"], saved: ["a": 1, "x": 3, "c": 99], count: 8), ["a": 1, "b": 0, "c": 2])
        // Once every color is used, colors repeat instead of failing.
        XCTAssertEqual(SiteColors.next(after: [0, 1], count: 2), 0)
    }
}
