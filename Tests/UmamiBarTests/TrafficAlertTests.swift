import XCTest
@testable import UmamiBar

final class TrafficAlertTests: XCTestCase {
    /// Seven days of hourly sessions: `daily` in every hour, with the last hours overridden.
    private func hours(daily: Double, last: [Double] = []) -> [Double] {
        var values = Array(repeating: daily, count: TrafficAlert.history)
        values.replaceSubrange((values.count - last.count)..., with: last)
        return values
    }
    func testZeroNeedsUsualTrafficInTheSameHours() {
        let broken = TrafficAlert.evaluate(hours(daily: 4, last: [0, 0, 0]))
        XCTAssertEqual(broken.map(\.kind), [.zero])
        XCTAssertEqual(broken.first?.usual, 12)
        // A small site that is usually quiet at this time stays silent.
        XCTAssertTrue(TrafficAlert.evaluate(hours(daily: 1, last: [0, 0, 0])).isEmpty)
        // One visit in the window is not a drop to zero.
        XCTAssertTrue(TrafficAlert.evaluate(hours(daily: 4, last: [0, 1, 0])).isEmpty)
    }
    func testSpikeNeedsRatioAndMinimum() {
        let spike = TrafficAlert.evaluate(hours(daily: 10, last: [30]))
        XCTAssertEqual(spike.map(\.kind), [.spike])
        XCTAssertEqual(spike.first?.recent, 30)
        XCTAssertTrue(TrafficAlert.evaluate(hours(daily: 10, last: [29])).isEmpty)
        // Tripling a tiny site is not a spike until it reaches the minimum.
        XCTAssertTrue(TrafficAlert.evaluate(hours(daily: 2, last: [19])).isEmpty)
        XCTAssertEqual(TrafficAlert.evaluate(hours(daily: 0, last: [20])).map(\.kind), [.spike])
        XCTAssertTrue(TrafficAlert.evaluate(Array(repeating: 0, count: 100) + [50]).isEmpty, "too little history")
    }
    func testAlertsFireOnceUntilCleared() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "TrafficAlertTests-\(UUID())"))
        let tracker = AlertTracker(defaults: defaults)
        let zero = TrafficAlert.Finding(kind: .zero, recent: 0, usual: 12)
        XCTAssertEqual(tracker.update(websiteID: "a", findings: [zero]), [zero])
        XCTAssertEqual(tracker.update(websiteID: "a", findings: [zero]), [], "still active: no repeat")
        XCTAssertEqual(tracker.update(websiteID: "b", findings: [zero]), [zero], "other sites are independent")
        XCTAssertEqual(tracker.update(websiteID: "a", findings: []), [])
        XCTAssertEqual(tracker.update(websiteID: "a", findings: [zero]), [zero], "fires again after clearing")
        tracker.keep(["b"])
        XCTAssertEqual(tracker.update(websiteID: "a", findings: [zero]), [zero], "unfollowed sites are forgotten")
        XCTAssertEqual(tracker.update(websiteID: "b", findings: [zero]), [])
    }
    func testWindowCoversCompleteHours() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 16, minute: 28))!
        let window = TrafficAlert.window(before: now, calendar: calendar)
        XCTAssertEqual(window.start, calendar.date(from: DateComponents(year: 2026, month: 10, day: 8, hour: 16)))
        let buckets = try TimeBuckets.expand([Point(x: "2026-10-15 15:00:00", y: 9)], start: window.start, end: window.end, component: .hour, calendar: calendar)
        XCTAssertEqual(buckets.count, TrafficAlert.history)
        XCTAssertEqual(buckets.last?.y, 9, "the last complete hour is last")
    }
    func testNoticeText() {
        let site = Website(id: "a", name: "Blog", domain: "blog.test")
        XCTAssertTrue(TrafficAlert.zero.notice(for: site, finding: .init(kind: .zero, recent: 0, usual: 12)).title.contains("Blog"))
        XCTAssertFalse(TrafficAlert.spike.notice(for: site, finding: .init(kind: .spike, recent: 25, usual: 0)).body.contains("inf"))
    }
}
