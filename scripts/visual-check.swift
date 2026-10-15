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
  if screen == "detail" { state.detailID = "2"; state.rows = [MetricRow(x:"/docs/quick-start",y:27),MetricRow(x:"/docs/api",y:16),MetricRow(x:"/docs/install",y:10),MetricRow(x:"/docs/guides",y:7),MetricRow(x:"/",y:4)] }
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
   print("Native navigation dispatch passed")
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
 let settings = SettingsWindowController(); let window = settings.window!
 window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
 var saved: [String] = []
 var savedColors: [String: Int] = [:]
 settings.onSave = { _, sites, colors in saved = sites.map(\.id); savedColors = colors }
 settings.show(.connection, connection: nil, sites: [], colors: [:])
 func controls<T: NSView>(_ type: T.Type, in view: NSView = window.contentView!) -> [T] { view.subviews.flatMap { ($0 as? T).map { [$0] } ?? [] + controls(type, in: $0) } }
 func tap(_ title: String) { controls(PaintedButton.self).first { $0.title == title }!.performClick(nil) }
 if let mock = ProcessInfo.processInfo.environment["UMAMIBAR_MOCK"] {
  let fields = controls(NSTextField.self).filter { $0.isEditable }
  fields.first { !($0 is NSSecureTextField) }!.stringValue = mock
  fields.first { $0 is NSSecureTextField }!.stringValue = "test-key"
  tap(L("验证并选择网站"))
  let deadline = Date().addingTimeInterval(5)
  while controls(WebsiteChoice.self).isEmpty && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
  let checks = controls(WebsiteChoice.self)
  print("Websites listed: \(checks.count)")
  if CommandLine.arguments.contains("--save-test") {
   checks.prefix(2).forEach { $0.performClick(nil) }
   tap(L("保存并查看"))
   precondition(saved.count == 2 && !window.isVisible, "Save failed: \(saved)")
   precondition(Set(savedColors.keys) == Set(saved) && Set(savedColors.values).count == 2, "Colors not saved: \(savedColors)")
   print("Settings save passed: \(saved) colors \(savedColors)")
   return
  }
  if screen == "settings-websites" { checks.prefix(3).forEach { $0.performClick(nil) }; precondition(controls(ColorSwatch.self).count == 3, "Swatches missing") }
 }
 tap(["settings-connection": L("连接"), "settings-websites": L("网站"), "settings-general": L("通用")][screen] ?? L("连接"))
 RunLoop.main.run(until: Date().addingTimeInterval(0.3))
 let frame = window.contentView!.superview!
 frame.display()
 if let bitmap = frame.bitmapImageRepForCachingDisplay(in: frame.bounds) { frame.cacheDisplay(in: frame.bounds, to: bitmap); try! bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "/tmp/native-\(appearance)-\(screen).png")) }
 print("Rendered \(appearance) \(screen): size \(frame.bounds.size)")
}
