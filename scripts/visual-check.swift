import AppKit
@main struct VisualCheck {
 static func main() {
  let app = NSApplication.shared; app.setActivationPolicy(.accessory)
  let appearance = CommandLine.arguments[1]
  let screen = CommandLine.arguments[2]
  if screen.hasPrefix("settings") { settingsCheck(appearance: appearance, screen: screen); return }
  let height: CGFloat = screen == "empty" ? 206 : 640
  let window = NSWindow(contentRect: NSRect(x:0,y:0,width:360,height:height), styleMask:[.borderless],backing:.buffered,defer:false)
  window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
  let panel = NativePanel(frame: NSRect(x:0,y:0,width:360,height:height));window.contentView=panel;window.orderFront(nil)
  let end = Date(); let sites = [Website(id:"1",name:"我的网站",domain:"example.com"),Website(id:"2",name:"产品文档",domain:"docs.example.com"),Website(id:"3",name:"个人博客",domain:"blog.example.com")]
  var state = PanelState(screen:screen,loading:false,period:.day,start:end.addingTimeInterval(-86400),end:end,updated:"刚刚更新",sites:sites.enumerated().map { i,s in PanelSite(website:s,total:[1,36,12][i],points:(0..<24).map { Point(x:"\($0):00",y:i == 0 ? ($0 == 18 ? 1 : 0) : Double(($0*13)%37)) },error:nil,color:i) })
  let fixture = try! JSONDecoder().decode(Stats.self, from: Data(#"{"visitors":36,"pageviews":64,"visits":40,"bounces":14,"totaltime":2808}"#.utf8))
  state.sites = state.sites.enumerated().map { index, site in
   PanelSite(website: site.website, total: site.total, points: site.points, error: nil, stats: fixture, previousVisitors: [0,30,16][index], color: [0,2,4][index])
  }
  if CommandLine.arguments.contains("--pinned") { state.sites[0].pinned = true }
  // Live counts: zero, someone online, and a failed request (shown as a dash, never as zero).
  if CommandLine.arguments.contains("--live") { for (i, value) in [0, 7, nil].enumerated() { state.sites[i].live = value; state.sites[i].liveFailed = value == nil } }
  if CommandLine.arguments.contains("--cached") {
   state.hasCachedData = true; state.start = state.start.addingTimeInterval(-3600); state.end = state.end.addingTimeInterval(-3600)
   state.updated = L("本地数据 · %@", Formats.time.string(from: state.end))
   for i in state.sites.indices { state.sites[i].cached = true; state.sites[i].savedAt = state.end; state.sites[i].rangeStart = state.start; state.sites[i].rangeEnd = state.end }
  }
  if screen == "detail" { state.detailID = "2"; state.rows = [MetricRow(x:"/docs/quick-start",y:27),MetricRow(x:"/docs/api",y:16),MetricRow(x:"/docs/install",y:10),MetricRow(x:"/docs/guides",y:7),MetricRow(x:"/",y:4)] }
  if let dimensionFlag = CommandLine.arguments.first(where: { $0.hasPrefix("--dimension=") }),
     let dimension = DetailDimension(rawValue: String(dimensionFlag.dropFirst("--dimension=".count))) {
   state.dimension = dimension; state.breakdown = dimension.category
   state.rows = [MetricRow(x: dimension == .country ? "CN" : "google", y: 27), MetricRow(x: "newsletter", y: 16), MetricRow(x: "very_long_campaign_name_for_autumn_product_launch", y: 10), MetricRow(x: nil, y: 7), MetricRow(x: "", y: 4)]
  }
  var actions: [String] = []
  panel.onAction = { name, _ in actions.append(name) }
  panel.render(state);panel.layoutSubtreeIfNeeded()
  if CommandLine.arguments.contains("--click-tests") {
   let expected = screen == "empty" ? L("退出 UmamiBar") : L("刷新数据")
   guard let button = panel.subviews.compactMap({ $0 as? PaintedButton }).first(where: { $0.title == expected }) else { fatalError("Missing button") }
   button.performClick(nil)
   precondition(actions == [screen == "empty" ? "quit" : "refresh"], "Wrong action: \(actions)")
   print("Button dispatch passed: \(actions)")
  }
  if CommandLine.arguments.contains("--hover"), let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
   for button in panel.subviews.compactMap({ $0 as? PaintedButton }) where button.style == .secondary || button.style == .destructive { button.mouseEntered(with: event) }
  }
  if CommandLine.arguments.contains("--navigation-tests") {
   state.screen = "overview"; panel.render(state)
   let scroll = panel.subviews.compactMap { $0 as? NSScrollView }.first!
   let card = scroll.documentView!.subviews.compactMap { $0 as? SiteCard }[1]
   // A data-only refresh must update the same views in place; an error row changes layout and rebuilds.
   state.loading = true; panel.render(state)
   precondition(panel.subviews.compactMap { $0 as? NSScrollView }.first === scroll && scroll.documentView!.subviews.compactMap { $0 as? SiteCard }[1] === card, "Overview rebuilt on data refresh")
   var failed = state; failed.sites[0] = PanelSite(website: failed.sites[0].website, total: nil, points: nil, error: "x"); panel.render(failed)
   precondition(panel.subviews.compactMap { $0 as? NSScrollView }.first !== scroll, "Layout change did not rebuild")
   state.loading = false; panel.render(state)
   let rebuilt = panel.subviews.compactMap { $0 as? NSScrollView }.first!
   let card2 = rebuilt.documentView!.subviews.compactMap { $0 as? SiteCard }[1]
   print("In-place overview update passed")
   card2.subviews.compactMap { $0 as? PaintedButton }.first!.performClick(nil)
   precondition(actions == ["detail"])
   actions = []; state.screen = "detail"; state.detailID = "2"; panel.render(state)
   let detailScroll = panel.subviews.compactMap { $0 as? NSScrollView }.first!
   let body = detailScroll.documentView as! DetailBody
   body.subviews.compactMap { $0 as? PaintedButton }.first { $0.title == L("流量来源") }!.performClick(nil)
   panel.subviews.compactMap { $0 as? PaintedButton }.first { $0.title == "‹" }!.performClick(nil)
   precondition(actions == ["breakdown", "back"])
   for dimension in [DetailDimension.utmCampaign, .city] {
    state.dimension = dimension; state.breakdown = dimension.category; panel.render(state)
    let popup = body.subviews.compactMap { $0 as? NSPopUpButton }.first!
    precondition(popup.selectedItem?.representedObject as? String == dimension.rawValue)
    precondition(popup.numberOfItems == DetailDimension.options(for: dimension.category).count)
    popup.selectItem(at: 0); actions = []
    NSApp.sendAction(popup.action!, to: popup.target, from: popup)
    precondition(actions == ["dimension"])
   }
   print("Native navigation and dimension dispatch passed")
  }
  panel.display()
  if let bitmap=panel.bitmapImageRepForCachingDisplay(in:panel.bounds) { panel.cacheDisplay(in:panel.bounds,to:bitmap);if let data=bitmap.representation(using:.png,properties:[:]) { try! data.write(to: URL(fileURLWithPath:"/tmp/native-\(appearance)-\(screen).png")) } }
  print("Rendered \(appearance) \(screen): \(panel.subviews.count) native controls; size \(panel.bounds.size)")
 }
}

/// Renders a settings tab (settings-connection / settings-websites / settings-general).
/// With UMAMIBAR_MOCK=http://127.0.0.1:PORT it verifies against that server first,
/// exercising the real connect → website list flow.
func settingsCheck(appearance: String, screen: String) {
 let originalLanguage = Localization.choice
 defer { Localization.set(originalLanguage) }
 let preferences = Preferences(defaults: UserDefaults(suiteName: "UmamiBar.visual.\(UUID().uuidString)")!)
 let directory = URL(fileURLWithPath: "/tmp/umamibar-visual-\(UUID().uuidString)")
 defer { try? FileManager.default.removeItem(at: directory) }
 let snapshots = SnapshotStore(directory: directory)
 let settings = SettingsWindowController(preferences: preferences, snapshots: snapshots); let window = settings.window!
 window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
 var saved: [Website] = []
 var savedColors: [String: Int] = [:]
 settings.onSave = { _, sites, colors in saved = sites; savedColors = colors }
 settings.show(.connection, connection: nil, sites: [], colors: [:])
 func controls<T: NSView>(_ type: T.Type, in view: NSView = window.contentView!) -> [T] { view.subviews.flatMap { ($0 as? T).map { [$0] } ?? [] + controls(type, in: $0) } }
 func tap(_ title: String) {
  guard let button = controls(PaintedButton.self).first(where: { $0.title == title }) else { fatalError("Missing button: \(title)") }
  button.performClick(nil)
 }
 func popup(_ label: String) -> ActionPopup { controls(ActionPopup.self).first { $0.identifier?.rawValue == label }! }
 func choose(_ label: String, _ raw: String) {
  let control = popup(label)
  control.select(control.itemArray.first { $0.representedObject as? String == raw })
  NSApp.sendAction(control.action!, to: control.target, from: control)
 }
 if let mock = ProcessInfo.processInfo.environment["UMAMIBAR_MOCK"] ?? CommandLine.arguments.first(where: { $0.hasPrefix("--mock=") }).map({ String($0.dropFirst(7)) }) {
  let fields = controls(NSTextField.self).filter { $0.isEditable }
  fields.first { !($0 is NSSecureTextField) }!.stringValue = mock
  fields.first { $0 is NSSecureTextField }!.stringValue = "test-key"
  tap(L("验证并选择网站"))
  let deadline = Date().addingTimeInterval(5)
  while controls(WebsiteSettingsRow.self).isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
  let checks = controls(CallbackCheckbox.self)
  precondition(checks.count >= 3, "Website discovery failed")
  print("Websites listed: \(checks.count)")
  if CommandLine.arguments.contains("--save-test") {
   checks.prefix(2).forEach { $0.performClick(nil) }
   tap(L("保存并查看"))
   precondition(saved.count == 2 && !window.isVisible, "Save failed: \(saved)")
   precondition(Set(savedColors.keys) == Set(saved.map(\.id)) && Set(savedColors.values).count == 2, "Colors not saved")
   print("Settings save passed: \(saved.map(\.id)) colors \(savedColors)")
   return
  }
  checks.prefix(3).forEach { $0.performClick(nil) }
  precondition(controls(ColorSwatch.self).count == 3, "Swatches missing")
  if CommandLine.arguments.contains("--preferences-tests") {
   tap(L("保存并查看"))
   let connection = Connection(base: try! Connection.baseURL(mock), key: "test-key")
   settings.show(.websites, connection: connection, sites: saved, colors: savedColors)
   let deadline = Date().addingTimeInterval(5)
   while controls(WebsiteSettingsRow.self).count < 4 && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
   RunLoop.main.run(until: Date().addingTimeInterval(0.1))
   let first = saved[0], second = saved[1]
   controls(PinButton.self).first { $0.toolTip == L("置顶 %@", second.name) }!.performClick(nil)
   controls(PinButton.self).first { $0.toolTip == L("置顶 %@", first.name) }!.performClick(nil)
   precondition(preferences.layout(for: connection.base, available: saved.map(\.id)).pinned == [second.id, first.id])
   let row = controls(WebsiteSettingsRow.self).first { $0.website.id == first.id }!
   row.subviews.compactMap { $0 as? PaintedButton }.first { $0.title == "⌃" }!.performClick(nil)
   precondition(preferences.layout(for: connection.base, available: saved.map(\.id)).pinned == [first.id, second.id])
   tap(L("通用")); choose(L("显示内容"), MenuDisplay.website.rawValue); choose(L("指定网站"), second.id)
   precondition(preferences.menuDisplay == .website && preferences.menuWebsiteID == second.id)
   let stats = try! JSONDecoder().decode(Stats.self, from: Data(#"{"visitors":3,"pageviews":5}"#.utf8))
   let end = Date()
   try! snapshots.save(SiteSnapshot(websiteID: first.id, period: 0, timezone: TimeZone.current.identifier, start: Period.day.start(before: end), end: end, savedAt: end, stats: stats, points: [Point(x: "x", y: 3)], previousVisitors: 2), base: connection.base)
   let toggle = controls(ActionSwitch.self).first { $0.identifier?.rawValue == L("保留最近成功数据") }!
   toggle.state = .off; NSApp.sendAction(toggle.action!, to: toggle.target, from: toggle)
   tap(L("取消")); precondition(preferences.retainData && snapshots.allRecords(base: connection.base).count == 1)
   let again = controls(ActionSwitch.self).first { $0.identifier?.rawValue == L("保留最近成功数据") }!
   again.state = .off; NSApp.sendAction(again.action!, to: again.target, from: again)
   tap(L("关闭并清除")); precondition(!preferences.retainData && snapshots.allRecords(base: connection.base).isEmpty)
   preferences.retainData = true
   print("Native pinning, ordering, menu source, and cache confirmation passed")
  }
 }
 if CommandLine.arguments.contains("--language-test") {
  tap(L("通用")); choose(L("语言"), "en")
  precondition(L("通用") == "General" && controls(PaintedButton.self).contains { $0.title == "General" }, "English not applied")
  choose(L("语言"), ""); precondition(Localization.choice == "", "System not restored")
  print("Language switch passed")
 }
 tap(["settings-connection": L("连接"), "settings-websites": L("网站"), "settings-general": L("通用")][screen] ?? L("连接"))
 RunLoop.main.run(until: Date().addingTimeInterval(0.3))
 let frame = window.contentView!.superview!
 frame.display()
 if let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) { frame.cacheDisplay(in: frame.bounds, to: bitmap); try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/native-\(appearance)-\(screen).png")) }
 print("Rendered \(appearance) \(screen): size \(frame.bounds.size)")
}
