import Foundation

/// API time series can omit empty buckets. Expand successful responses onto a
/// calendar-aligned timeline; preserve partial first/last buckets and DST hours.
enum TimeBuckets {
    static func expand(_ points: [Point], period: Period, end: Date, calendar: Calendar = .current, wallClockLabels: Bool = false) throws -> [Point] {
        let start = period.start(before: end, calendar: calendar)
        let component: Calendar.Component = period == .day ? .hour : .day
        guard var cursor = calendar.dateInterval(of: component, for: start)?.start else { return [] }
        let iso = ISO8601DateFormatter()
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.calendar = calendar
        local.timeZone = calendar.timeZone
        let label = DateFormatter()
        label.locale = Locale(identifier: "zh_CN")
        label.calendar = calendar
        label.timeZone = calendar.timeZone
        label.dateFormat = "MM/dd HH:mm Z"
        func parse(_ input: String) -> Date? {
            // Umami's timezone-grouped SQL timestamp can serialize as a Z-suffixed
            // Date even though its components already represent the requested zone.
            if wallClockLabels && input.hasSuffix("Z") {
                let wallClock = String(input.dropLast())
                for format in ["yyyy-MM-dd'T'HH:mm:ss.SSS", "yyyy-MM-dd'T'HH:mm:ss"] {
                    local.dateFormat = format
                    if let date = local.date(from: wallClock) { return date }
                }
            }
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso.date(from: input) { return date }
            iso.formatOptions = [.withInternetDateTime]
            if let date = iso.date(from: input) { return date }
            for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
                local.dateFormat = format
                if let date = local.date(from: input) { return date }
            }
            return nil
        }
        var values: [Date: Double] = [:]
        let first = cursor
        for point in points {
            guard let date = parse(point.x), let bucket = calendar.dateInterval(of: component, for: date)?.start else {
                throw ServiceError.message("时间序列日期格式不兼容，无法定位时间桶。")
            }
            guard bucket >= first, bucket <= end else { continue }
            values[bucket, default: 0] += point.y
        }
        var result: [Point] = []
        while cursor < end {
            guard let next = calendar.date(byAdding: component, value: 1, to: cursor), next > cursor else { break }
            let lower = max(cursor, start)
            let upper = min(next, end)
            result.append(Point(x: label.string(from: lower) + " — " + label.string(from: upper), y: values[cursor] ?? 0))
            cursor = next
        }
        if points.contains(where: { $0.y > 0 }) && !result.contains(where: { $0.y > 0 }) {
            throw ServiceError.message("趋势时间与查询范围不一致，无法显示；请重试。")
        }
        return result
    }
}
