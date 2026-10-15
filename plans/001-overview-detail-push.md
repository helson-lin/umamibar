# 001 — Slide between overview and detail in the popover

- **Status**: DONE
- **Commit**: f2f7f7c
- **Severity**: MEDIUM (missed opportunity, additive)
- **Category**: 8. Missed opportunities (with 1. Purpose & frequency, 6. Accessibility)
- **Estimated scope**: 3 files (`Components.swift`, `NativePanel.swift`, `App.swift`), ~30 lines

## Problem

UmamiBar is a native AppKit menu bar app. Its popover content is one custom-drawn view, `NativePanel`. Clicking a site card opens that site's **detail** screen, and the back button `‹` returns to the **overview**. Right now both moves happen instantly: `render(_:)` removes every subview and draws the new screen in one frame. Nothing shows that detail is a level *below* the overview, so the screen just swaps.

The swap happens in `NativePanel.render(_:)`, which purges subviews and rebuilds them:

```swift
// Sources/UmamiBar/NativePanel.swift:44-45 — current
        state = next
        subviews.forEach { if !(reuseOverview && $0 === overviewScroll) && !(reuseDetail && $0 === detailScroll) { $0.removeFromSuperview() } }
```

```swift
// Sources/UmamiBar/NativePanel.swift:101 — current (end of render)
        previousScreen = next.screen; needsDisplay = true
```

The panel is not layer-backed today:

```swift
// Sources/UmamiBar/App.swift:133 — current (MainController.loadView)
        panel = NativePanel(); panel.translatesAutoresizingMaskIntoConstraints = false
```

How often this happens: a few times a day, and only when the user chooses to drill in. That is "occasional", so a standard transition is justified. Keyboard-initiated navigation must stay instant:

- Return/Space on a focused chart opens detail.
- Esc (`cancelOperation`, `NativePanel.swift:25-27`) goes back.

## Target

- **Overview → detail**, pointer-initiated: the new screen pushes in from the right (`CATransition` type `.push`, subtype `.fromRight`). Duration **250ms**, strong ease-out **`cubic-bezier(0.23, 1, 0.32, 1)`**.
- **Detail → overview**, pointer-initiated: same, subtype `.fromLeft`.
- **Keyboard-initiated** navigation (Return/Space on a chart, Esc): no animation.
- **Reduce motion** (`NSWorkspace.shared.accessibilityDisplayShouldReduceMotion`): a `.fade` of **150ms** with the same ease-out curve. Opacity feedback stays and movement is dropped.
- Everything else stays instant. That includes period switches, refreshes, the empty state and the settings window.
- The sliding content is clipped to the panel's rounded surface (corner radius **18**, the same radius `drawSurface(bounds, radius: 18)` uses).

## Repo conventions to follow

- Shared design primitives live in `Sources/UmamiBar/Components.swift`, next to `enum Ink` and `enum Formats`. There are no motion tokens yet; this plan adds `enum Motion` there.
- The code is dense AppKit with `;`-joined statements and short `//` comments that explain *why*. Match that style.
- Minimum target is **macOS 10.15**. `CATransition` and `accessibilityDisplayShouldReduceMotion` are both available there. AppKit already imports QuartzCore, so no new import is needed.

## Steps

1. **Add motion tokens** to `Sources/UmamiBar/Components.swift`, directly above the line `/// Shared date formatters: building a DateFormatter on every draw() is expensive.` (currently line 33).
   - If an `enum Motion` already exists (plan 002 may have added it), replace it with this exact block.
   - Plan 002 uses the same block, so don't rename or trim members.

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

2. **Make the panel layer-backed** in `Sources/UmamiBar/App.swift`, `MainController.loadView()`. Replace line 133:

   ```swift
           panel = NativePanel(); panel.translatesAutoresizingMaskIntoConstraints = false
   ```

   with:

   ```swift
           panel = NativePanel(); panel.translatesAutoresizingMaskIntoConstraints = false
           // Layer-backed so screen changes can slide; clip to the 18pt surface so content never slides outside it.
           panel.wantsLayer = true; panel.layer?.masksToBounds = true; panel.layer?.cornerRadius = 18
   ```

3. **Add the transition** in `Sources/UmamiBar/NativePanel.swift`, `render(_:)`. Insert these lines immediately **before** line 44 (`        state = next`), so the transition is attached before the subviews change:

   ```swift
           // Pointer-initiated overview <-> detail navigation slides to show hierarchy; keyboard (Return on a chart, Esc) stays instant.
           let push: CATransitionSubtype? = previousScreen == "overview" && next.screen == "detail" ? .fromRight : previousScreen == "detail" && next.screen == "overview" ? .fromLeft : nil
           var transitioned = false
           if let push = push, let type = NSApp.currentEvent?.type, [.leftMouseDown, .leftMouseUp].contains(type), let layer = layer {
               let transition = CATransition()
               transition.type = Motion.reduced ? .fade : .push; transition.subtype = push
               transition.duration = Motion.reduced ? 0.15 : 0.25; transition.timingFunction = Motion.easeOutTiming
               layer.add(transition, forKey: kCATransition); transitioned = true
           }
   ```

4. **Draw the new screen in the same transaction.** At the end of `render(_:)`, replace line 101:

   ```swift
           previousScreen = next.screen; needsDisplay = true
   ```

   with:

   ```swift
           previousScreen = next.screen; needsDisplay = true
           // The header text is drawn in draw(_:), not by subviews; render it now so it slides with its screen.
           if transitioned { displayIfNeeded() }
   ```

## Boundaries

- Do NOT animate anything else: period switches, refresh, the empty screen, the settings window or the status item.
- Do NOT change layout, frames, colors or the in-place update logic in `render(_:)` (lines 33-38, `reuseOverview` / `reuseDetail`).
- Do NOT add dependencies or new files.
- `scripts/visual-check.swift` renders without real events, so `NSApp.currentEvent` is nil there and the transition never runs. Do not change the script.
- If the code at the cited lines doesn't match (drift since `f2f7f7c`), STOP and report instead of improvising.

## Verification

- **Mechanical**:
  - `swift build --scratch-path /tmp/umamibar-plan` completes with no errors.
  - `swift test --scratch-path /tmp/umamibar-plan` reports `Executed 8 tests, with 0 failures`.
  - `./scripts/build-app.sh native` prints `Built: …`.
  - Rebuild and run the visual check (the command is in `README.md`, section on the native rendering check) with `light overview --click-tests` and `dark detail --navigation-tests`. Both pass, and the PNGs in `/tmp/native-*.png` look the same as before. This confirms layer-backing changed no static rendering: text stays crisp and corners stay rounded.
- **Feel check** (run `dist/UmamiBar.app`, open the popover):
  - Click a site card. Detail slides in from the right, and the overview leaves to the left. The site name in the header moves *with* the detail screen and does not pop in after the slide.
  - Click `‹`. The overview slides back in from the left.
  - Focus a chart with Tab and press Return to open detail. It appears **instantly**. Press Esc. Overview appears **instantly**.
  - Click a card and immediately click `‹` several times quickly. The panel never gets stuck half-way or blank, and it always ends on the right screen.
  - Content never slides outside the rounded panel corners.
  - Turn on System Settings → Accessibility → Display → Reduce motion. Clicking a card now crossfades over 150ms with no horizontal movement.
  - If 250ms feels long next to the system popover animation, try **200ms**. Do not go below 180ms or above 300ms.
- **Done when**: pointer navigation between overview and detail slides in the correct direction, keyboard navigation and every other state change stay instant, and Reduce motion gives a short fade.
