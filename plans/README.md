# Animation plans

Implementation plans from the animation audit at commit `f2f7f7c`. Each plan is self-contained: an executor needs only the plan file and the repo.

The audit found **no corrective issues**. The app draws its UI with AppKit and has almost no custom motion. Hover, keyboard navigation and tab switches are instant, which is correct for how often they happen, and the system popover and spinner animations are kept as macOS draws them. These plans are additive.

| # | Plan | Severity | Status |
| --- | --- | --- | --- |
| 001 | [Slide between overview and detail in the popover](001-overview-detail-push.md) | MEDIUM | DONE |
| 002 | [Grow chart bars in when trend data arrives](002-chart-bars-grow-in.md) | LOW | DONE |

## Recommended order

1. **001** first. It adds the shared `enum Motion` tokens to `Sources/UmamiBar/Components.swift`.
2. **002** next. It needs the same `enum Motion` block. Plan 002 adds the identical block if it is missing, so it can also run alone.

The plans touch different code, except that both define `enum Motion` with identical content. Running them in parallel works only if the second one to land reconciles that block, so run them one after the other.

## Not planned

- **Error row layout jump.** When a site's refresh fails, its card grows by 30pt and the cards below jump down instantly. This happens rarely and was not selected.
