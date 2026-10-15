import AppKit
@main struct VisualCheck {
 static func main() {
  let app = NSApplication.shared; app.setActivationPolicy(.accessory)
  let appearance = CommandLine.arguments[1]
  let screen = CommandLine.arguments[2]
  let height: CGFloat = screen == "setup" ? 418 : screen == "selection" ? 520 : 640
  let window = NSWindow(contentRect: NSRect(x:0,y:0,width:360,height:height), styleMask:[.borderless],backing:.buffered,defer:false)
  window.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
  let panel = NativePanel(frame: NSRect(x:0,y:0,width:360,height:height));window.contentView=panel;window.orderFront(nil)
  let end = Date(); let sites = [Website(id:"1",name:"我的网站",domain:"example.com"),Website(id:"2",name:"产品文档",domain:"docs.example.com"),Website(id:"3",name:"个人博客",domain:"blog.example.com")]
  var state = PanelState(screen:screen,server:"https://api.umami.is/v1",hasKey:false,connecting:false,loading:false,period:.day,start:end.addingTimeInterval(-86400),end:end,updated:"刚刚更新",message:"",sites:sites.enumerated().map { i,s in PanelSite(website:s,total:[1,36,12][i],points:(0..<24).map { Point(x:"\($0):00",y:i == 0 ? ($0 == 18 ? 1 : 0) : Double(($0*13)%37)) },error:nil) },available:sites,selected:["1"])
  let fixture = try! JSONDecoder().decode(Stats.self, from: Data(#"{"visitors":36,"pageviews":64,"visits":40,"bounces":14,"totaltime":2808}"#.utf8))
  state.sites = state.sites.enumerated().map { index, site in
   PanelSite(website: site.website, total: site.total, points: site.points, error: nil, stats: fixture, previousVisitors: [0,30,16][index])
  }
  if screen == "detail" { state.detailID = "2"; state.rows = [MetricRow(x:"/docs/quick-start",y:27),MetricRow(x:"/docs/api",y:16),MetricRow(x:"/docs/install",y:10),MetricRow(x:"/docs/guides",y:7),MetricRow(x:"/",y:4)] }
  var actions: [String] = []
  panel.onAction = { name, _ in actions.append(name) }
  panel.render(state);panel.layoutSubtreeIfNeeded()
  if CommandLine.arguments.contains("--click-tests") {
   let expected = screen == "setup" ? "退出 UmamiBar" : "刷新数据"
   guard let button = panel.subviews.compactMap({ $0 as? PaintedButton }).first(where: { $0.title == expected }) else { fatalError("Missing button") }
   button.performClick(nil)
   precondition(actions == [screen == "setup" ? "quit" : "refresh"], "Wrong action: \(actions)")
   print("Button dispatch passed: \(actions)")
  }
  if CommandLine.arguments.contains("--hover"), let event = NSEvent.mouseEvent(with: .mouseMoved, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
   for button in panel.subviews.compactMap({ $0 as? PaintedButton }) where button.style == .secondary || button.style == .destructive { button.mouseEntered(with: event) }
  }
  if CommandLine.arguments.contains("--navigation-tests") {
   state.screen = "overview"; panel.render(state)
   let scroll = panel.subviews.compactMap { $0 as? NSScrollView }.first!
   let card = scroll.documentView!.subviews.compactMap { $0 as? SiteCard }[1]
   card.subviews.compactMap { $0 as? PaintedButton }.first!.performClick(nil)
   precondition(actions == ["detail"])
   actions = []; state.screen = "detail"; state.detailID = "2"; panel.render(state)
   let detailScroll = panel.subviews.compactMap { $0 as? NSScrollView }.first!
   let body = detailScroll.documentView as! DetailBody
   body.subviews.compactMap { $0 as? PaintedButton }.first { $0.title == "流量来源" }!.performClick(nil)
   panel.subviews.compactMap { $0 as? PaintedButton }.first { $0.title == "‹" }!.performClick(nil)
   precondition(actions == ["breakdown", "back"])
   print("Native navigation dispatch passed")
  }
  panel.display()
  if let bitmap=panel.bitmapImageRepForCachingDisplay(in:panel.bounds) { panel.cacheDisplay(in:panel.bounds,to:bitmap);if let data=bitmap.representation(using:.png,properties:[:]) { try! data.write(to: URL(fileURLWithPath:"/tmp/native-\(appearance)-\(screen).png")) } }
  print("Rendered \(appearance) \(screen): \(panel.subviews.count) native controls; size \(panel.bounds.size)")
 }
}
