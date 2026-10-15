# 002 — Grow chart bars in when trend data arrives

- **Status**: DONE
- **Commit**: f2f7f7c
- **Severity**: LOW (missed opportunity, additive)
- **Category**: 8. Missed opportunities (with 2. Easing & duration, 6. Accessibility)
- **Estimated scope**: 2 files (`Components.swift`, `ChartView.swift`), ~35 lines

## Problem

UmamiBar is a native AppKit menu bar app. Each site card in the popover draws a bar chart with a custom `NSView`, `ChartView`, inside `draw(_:)`. When the user switches the time range, the app clears the cached series. Each card first shows "正在加载…" with an empty chart, and when the request returns all bars appear at full height in a single frame. The design prototype in `index.html` intended motion here (`@media(prefers-reduced-motion:no-preference){.bar{transition:height .2s ease}}`), but the native view drops it.

Bars are drawn at their final height with no notion of progress:

```swift
// Sources/UmamiBar/ChartView.swift:8 — current
    var points: [Point] = [] { didSet { rebuildTracking(); needsDisplay = true } }
```

```swift
// Sources/UmamiBar/ChartView.swift:26-28 — current
        guard !points.isEmpty else { return }
        let step = chart.width / CGFloat(points.count)
        for (index, point) in points.enumerated() {
```

```swift
// Sources/UmamiBar/ChartView.swift:35 — current
            let height = max(2, CGFloat(point.y / maxValue) * chart.height)
```

```swift
// Sources/UmamiBar/ChartView.swift:43-44 — current (last line of the bar loop and its closing brace)
            NSGradient(starting: hovered == index ? .init(srgbRed: 1, green: 223/255, blue: 197/255, alpha: 1) : color.0, ending: color.1)?.draw(in: shape, angle: 90)
        }
```

How often this happens:

- **Data arrives into an empty chart.** This occurs on a time-range switch, the first load after saving settings, and the first load after a failure. It is occasional, so a short entrance is justified.
- **The 60-second auto-refresh.** These updates go through `SiteCard.update` / `DetailBody.update`, which set `points` on the **same** `ChartView` with data that is already there. They must **not** animate. Replaying a growth every minute would be decorative noise.
- **Re-opening the popover with cached data.** This builds charts while they are not yet in a window. It must **not** animate either.

## Target

- Animate only when `points` goes from **empty → non-empty** while the view is **in a window**.
- **Growth**: every non-zero bar grows from the baseline to its final height over **220ms** with the strong ease-out **`cubic-bezier(0.23, 1, 0.32, 1)`**. Entering motion uses ease-out, and 220ms stays within the 150–250ms budget.
- All bars grow together, with no stagger. A trend has up to 31 bars, and any stagger at 30–80ms would push the entrance far past 300ms.
- Empty-bucket baseline ticks (`point.y == 0`) and the dashed grid do not animate.
- **Reduce motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`): no growth. Bars draw at final height and fade from alpha 0 to 1 over the same 220ms curve.
- If `points` changes mid-growth (new data), do not restart. The growth continues toward the new heights, because heights are computed from the current points every frame.
- The hover tooltip keeps working during and after growth.

Why a timer and not Core Animation: bars are drawn with `NSBezierPath` and `NSGradient` in `draw(_:)` together with the grid and the tooltip. There is no per-bar layer to animate. Redrawing a ≤31-bar chart at 60 fps for 220ms is cheap. Do not restructure the view into layers for this.

## Repo conventions to follow

- Shared tokens live in `Sources/UmamiBar/Components.swift` (`enum Ink`, `enum Formats`). Motion tokens go in `enum Motion` there, shared with plan 001.
- `ChartView` uses short `//` comments explaining *why*, and `[weak self]` in closures. Match that.
- Minimum target is **macOS 10.15**: use `Timer` plus `CACurrentMediaTime()`. Don't use `NSView.displayLink`, which requires macOS 14.

## Steps

1. **Add motion tokens** to `Sources/UmamiBar/Components.swift`, directly above the line `/// Shared date formatters: building a DateFormatter on every draw() is expensive.` (currently line 33).
   - If an `enum Motion` already exists (plan 001 adds the same block), make sure it matches this block exactly and do nothing else.

   ```swift
   /// Motion tokens. Entrances use a strong ease-out: cubic-bezier(0.23, 1, 0.32, 1).
   enum Motion {
       static var easeOutTiming: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.23, 1, 0.32, 1) }
       /// System "Reduce motion": keep opacity feedback, drop movement.
       static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
       /// The ease-out curve evaluated at linear progress x in 0...1, for timer-driven drawing.
       static func easeOutProgress(_ x: Double) -> Double { bezier(x, 0.23, 1, 0.32, 1) }
       /// CSS cubic-bezier timing function: solves for t at time x by bisection, returns the eased value.
       static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
           if x <= 0 { return 0 }; if x >= 1 { return 1 }
           func coord(_ t: Double, _ p1: Double, _ p2: Double) -> Double { let u = 1 - t; return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t }
           var lo = 0.0, hi = 1.0, t = x
           for _ in 0..<30 { let value = coord(t, x1, x2); if abs(value - x) < 1e-5 { break }; if value < x { lo = t } else { hi = t }; t = (lo + hi) / 2 }
           return coord(t, y1, y2)
       }
   }
   ```

2. **Trigger growth only on first data.** In `Sources/UmamiBar/ChartView.swift`, replace line 8:

   ```swift
       var points: [Point] = [] { didSet { rebuildTracking(); needsDisplay = true } }
   ```

   with:

   ```swift
       // Bars grow in only when data first arrives into an empty, on-screen chart; refreshes with existing data stay still.
       var points: [Point] = [] { didSet { if oldValue.isEmpty && !points.isEmpty && window != nil { startGrowth() }; rebuildTracking(); needsDisplay = true } }
       private static let growthDuration: CFTimeInterval = 0.22
       private var growthStart: CFTimeInterval?
       private var growthTimer: Timer?
       /// Eased 0...1 progress of the current growth; 1 when idle.
       private var growth: CGFloat {
           guard let start = growthStart else { return 1 }
           return CGFloat(Motion.easeOutProgress(min(1, max(0, (CACurrentMediaTime() - start) / Self.growthDuration))))
       }
       private func startGrowth() {
           growthTimer?.invalidate(); growthStart = CACurrentMediaTime()
           let timer = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] timer in
               guard let self = self, let start = self.growthStart else { timer.invalidate(); return }
               if CACurrentMediaTime() - start >= Self.growthDuration { self.growthStart = nil; timer.invalidate() }
               self.needsDisplay = true
           }
           // .common keeps the growth running while the user scrolls the card list.
           RunLoop.main.add(timer, forMode: .common); growthTimer = timer
       }
       override func viewDidMoveToWindow() {
           super.viewDidMoveToWindow()
           if window == nil { growthTimer?.invalidate(); growthTimer = nil; growthStart = nil }
       }
   ```

3. **Apply progress while drawing bars.** In `draw(_:)`:

   a. Replace lines 26-28:

   ```swift
           guard !points.isEmpty else { return }
           let step = chart.width / CGFloat(points.count)
           for (index, point) in points.enumerated() {
   ```

   with:

   ```swift
           guard !points.isEmpty else { return }
           let step = chart.width / CGFloat(points.count)
           // Reduce motion: bars keep their height and fade in instead of growing.
           let reduced = Motion.reduced, progress = growth
           NSGraphicsContext.saveGraphicsState()
           if reduced { NSGraphicsContext.current?.cgContext.setAlpha(progress) }
           for (index, point) in points.enumerated() {
   ```

   b. Replace line 35:

   ```swift
               let height = max(2, CGFloat(point.y / maxValue) * chart.height)
   ```

   with:

   ```swift
               let height = max(2, CGFloat(point.y / maxValue) * chart.height * (reduced ? 1 : progress))
   ```

   c. Replace lines 43-44 (the gradient draw line and the `}` that closes the bar loop) with the same two lines plus a restore after the loop:

   ```swift
               NSGradient(starting: hovered == index ? .init(srgbRed: 1, green: 223/255, blue: 197/255, alpha: 1) : color.0, ending: color.1)?.draw(in: shape, angle: 90)
           }
           NSGraphicsContext.restoreGraphicsState()
   ```

   The hover tooltip block that follows (`if let index = hovered, …`) must stay **after** the restore, so the tooltip is never faded.

## Boundaries

- Do NOT animate on refresh (non-empty → non-empty), on hover, on keyboard arrow navigation, or when the chart is built off-screen.
- Do NOT change colors, bar geometry, the zero-bucket ticks, the grid, the tooltip or tracking areas.
- Do NOT touch `NativePanel.swift`, `App.swift` or the settings window.
- Do NOT add dependencies or convert the chart to CALayers.
- If the code at the cited lines doesn't match (drift since `f2f7f7c`), STOP and report instead of improvising.

## Verification

- **Mechanical**:
  - `swift build --scratch-path /tmp/umamibar-plan` completes with no errors.
  - `swift test --scratch-path /tmp/umamibar-plan` reports `Executed 8 tests, with 0 failures`.
  - Rebuild and run the visual check (command in `README.md`, native rendering check section) for `light overview` and `dark detail --navigation-tests`. The PNGs in `/tmp/native-*.png` show bars at **full** height. Those charts are built off-screen, so they must not be caught mid-growth.
- **Feel check** (run `dist/UmamiBar.app` with a real or local Umami server and open the popover):
  - Switch from 最近 24 小时 to 最近 7 天. When data lands, every card's bars rise from the baseline together in about a fifth of a second, fast at the start and settling gently. Nothing bounces or overshoots.
  - Leave the popover open past a 60-second auto-refresh. Bars do **not** replay the growth.
  - Close and reopen the popover. Bars are already at full height with no growth.
  - Hover over a bar during growth. The tooltip appears at full opacity and shows the correct value.
  - Scroll the card list while bars are growing. The growth keeps running.
  - Record the screen and step frame by frame. The first frame after data arrives shows short bars (not full height, not missing). Bars reach final height within about 13 frames at 60 fps.
  - Turn on System Settings → Accessibility → Display → Reduce motion and switch the range again. Bars appear at full height and fade in over 220ms with no vertical movement.
- **Done when**: bars grow in exactly when data first arrives in an on-screen chart, nowhere else, and Reduce motion gives a fade instead.
