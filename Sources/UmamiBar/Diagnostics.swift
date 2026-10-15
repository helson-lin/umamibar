import Foundation

/// Explicit local diagnostic mode. Never prints credentials, URLs or website IDs.
enum Diagnostics {
    static func run() {
        guard let address = UserDefaults.standard.string(forKey: "server"), let base = try? Connection.baseURL(address), let key = Keychain.read(),
              let data = UserDefaults.standard.data(forKey: "sites"), let sites = try? JSONDecoder().decode([Website].self, from: data) else {
            print("No saved connection available."); return
        }
        let api = API(); let connection = Connection(base: base, key: key); let end = Date()
        var pending = sites.count
        if pending == 0 { return }
        for (index, site) in sites.enumerated() {
            api.get(Series.self, connection: connection, path: "websites/\(site.id)/pageviews", query: Period.day.query(end: end)) { result in
                switch result {
                case .failure: print("site \(index): request failed")
                case .success(let series):
                    let expanded = try? TimeBuckets.expand(series.sessions, period: .day, end: end, wallClockLabels: true)
                    print("site \(index): raw=\(series.sessions.count), rawSum=\(series.sessions.reduce(0){$0+$1.y}), expandedSum=\(expanded?.reduce(0){$0+$1.y} ?? -1), timezone=\(TimeZone.current.identifier)")
                    for point in series.sessions.prefix(3) { print("time=\(point.x), count=\(point.y)") }
                }
                pending -= 1
                if pending == 0 { CFRunLoopStop(CFRunLoopGetMain()) }
            }
        }
        CFRunLoopRun()
    }

    static func details() {
        guard let address = UserDefaults.standard.string(forKey: "server"), let base = try? Connection.baseURL(address), let key = Keychain.read(), let data = UserDefaults.standard.data(forKey: "sites"), let sites = try? JSONDecoder().decode([Website].self, from: data), !sites.isEmpty else { print("No saved connection"); return }
        let api = API(); let connection = Connection(base: base, key: key); let end = Date(); var pending = sites.count * 3
        func done() { pending -= 1; if pending == 0 { CFRunLoopStop(CFRunLoopGetMain()) } }
        for (index, site) in sites.enumerated() {
            api.get(Stats.self, connection: connection, path: "websites/\(site.id)/stats", query: Period.day.query(end: end)) { result in
                switch result {
                case .success(let stats): print("site \(index): stats decoded; views present=\(stats.pageviews != nil), bounce=\(stats.bounceText), duration=\(stats.durationText)")
                case .failure: print("site \(index): stats request failed")
                }; done()
            }
            for dimension in ["path", "referrer"] {
                api.get([MetricRow].self, connection: connection, path: "websites/\(site.id)/metrics", query: Period.day.query(end: end) + [URLQueryItem(name: "type", value: dimension), URLQueryItem(name: "limit", value: "5")]) { result in
                    switch result {
                    case .success(let rows): print("site \(index): \(dimension) decoded \(rows.count) rows")
                    case .failure: print("site \(index): \(dimension) request failed")
                    }; done()
                }
            }
        }
        CFRunLoopRun()
    }
}
