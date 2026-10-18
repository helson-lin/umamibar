<p align="center">
  <img src="assets/AppIcon-preview.png" width="128" height="128" alt="UmamiBar app icon">
</p>

<h1 align="center">UmamiBar</h1>

<p align="center">
  <a href="https://github.com/helson-lin/umamibar/actions/workflows/ci.yml"><img src="https://github.com/helson-lin/umamibar/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/helson-lin/umamibar/releases"><img src="https://img.shields.io/github/v/release/helson-lin/umamibar?style=flat-square" alt="GitHub Release"></a>
</p>



<p align="center">Native Umami analytics for your macOS menu bar</p>

<p align="center">
  <a href="#requirements" title="Intel: macOS 10.15+; Apple Silicon: macOS 11+"><img src="https://img.shields.io/badge/macOS-10.15%2B-222222?style=flat-square&amp;logo=apple&amp;logoColor=white" alt="macOS deployment target 10.15+"></a>
  <img src="https://img.shields.io/badge/Swift-5.9%2B-F05138?style=flat-square&amp;logo=swift&amp;logoColor=white" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/UI-AppKit-3478F6?style=flat-square" alt="Native AppKit UI">
  <img src="https://img.shields.io/badge/Architecture-Universal-555555?style=flat-square" alt="Intel and Apple Silicon universal build">
  <img src="https://img.shields.io/badge/Status-In%20development-E89A57?style=flat-square" alt="In development">
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a>
</p>

A lightweight macOS menu bar client for Umami. Keep multiple websites in one popover, track traffic changes, and open a site's details without leaving your workflow.

Built with **AppKit**, native drawing, `URLSession`, and macOS Keychain. The app does not embed WebKit or require a local web server. The HTML prototype is a separate design reference.

## Contents

- [Features](#features)
- [Screenshots](#screenshots)
- [Requirements](#requirements)
- [Homebrew installation](#homebrew-installation)
- [Build and run](#build-and-run)
- [Connect Umami](#connect-umami)
- [Explore your websites](#explore-your-websites)
- [Data definitions](#data-definitions)
- [Development and checks](#development-and-checks)
- [Project structure](#project-structure)
- [Troubleshooting and current limits](#troubleshooting-and-current-limits)

## Features

- **Multiple websites:** visitor totals, compact session charts, and traffic quality metrics in one list.
- **Three time ranges:** last 24 hours, last 7 days, and last month.
- **Period comparisons:** visitor changes against the preceding interval of equal length, with a separate “New” state when the previous count is zero.
- **Website details:** click a website name or chart for a larger session chart, top pages, and traffic sources.
- **Native interactions:** chart hover values, keyboard navigation within charts, and return to the previous overview scroll position.
- **Automatic appearance:** light and dark themes follow macOS, with glass surfaces and warm orange charts.
- **Native menu bar sizing:** a system square for icon-only mode and content-based width for numbers, with monospaced digits, compact large numbers, and exact counts in the tooltip.
- **Refresh feedback:** a spinner while loading, a timestamp with seconds, and periodic refresh while the popover is open.
- **Secure credentials:** API keys are stored in Keychain; website selections and preferences are stored locally.

> The documentation is available in English and Chinese. The current app interface is in Chinese; an in-app language switch is not implemented.

## Screenshots

| Mode | Overview | Website details |
| --- | --- | --- |
| Dark | <img src="docs/previews/dark-overview.png" width="260" alt="Overview in dark mode"> | <img src="docs/previews/dark-detail.png" width="260" alt="Website details in dark mode"> |
| Light | <img src="docs/previews/light-overview.png" width="260" alt="Overview in light mode"> | <img src="docs/previews/light-detail.png" width="260" alt="Website details in light mode"> |

Sample data.

## Requirements

| Component | Requirement |
| --- | --- |
| Intel Mac | Deployment target: macOS 10.15 Catalina or later |
| Apple Silicon Mac | Deployment target: macOS 11 or later |
| Build tools | Xcode with a macOS SDK and Swift 5.9 or later |
| Umami | A deployment supporting Bearer API key authentication |

The app uses Sparkle 2 for automatic update checks and manual checks in **Settings → General → Check for Updates**. In-app updates use signed, notarized tagged releases; CI builds are ad-hoc signed and are not updateable. Sparkle is the sole third-party Swift package dependency.


## Homebrew installation

After the first release is published and its Cask update PR is merged:

```sh
brew tap helson-lin/umamibar https://github.com/helson-lin/umamibar
brew install --cask helson-lin/umamibar/umamibar
```

Upgrade with `brew update`, then `brew upgrade --cask helson-lin/umamibar/umamibar`. Homebrew's own legacy macOS support is separate from the app's deployment target. Older Macs can use the release ZIP directly.

Download the universal **DMG** from [Releases](https://github.com/helson-lin/umamibar/releases/latest), open it, and drag **UmamiBar.app** to **Applications**. Eject the disk image, then launch from Applications. Signed release builds support automatic Sparkle checks and manual checks in **Settings → General → Check for Updates**. Homebrew users update with the command above.

CI tests and packages the universal app on Intel and Apple Silicon for every branch push, pull request, and manual run. No tag is needed: open [Actions → CI](https://github.com/helson-lin/umamibar/actions/workflows/ci.yml), select a successful run, and download either `UmamiBar-macos-15` or `UmamiBar-macos-15-intel` from the summary (both contain a universal app; retained for 14 days; GitHub sign-in required). Extract the artifact, unzip the inner `UmamiBar-<version>-universal.zip`, and move `UmamiBar.app` to Applications. To package manually, select **Run workflow** and the desired branch.

Push a `vX.Y.Z` tag matching `VERSION` to publish the DMG, ZIP, SHA-256 checksums, signed Sparkle appcast, and generated Cask, then open a Cask update PR. See [RELEASING.md](docs/RELEASING.md) for setup and release instructions.

Tagged releases require Developer ID signing, Apple notarization, and the `SPARKLE_EDDSA_PRIVATE_KEY` Actions secret; see [release setup](docs/RELEASING.md#developer-id-signing-and-notarization). Ordinary CI builds remain ad-hoc signed and unnotarized. Existing releases are unchanged.

## Build and run

From the repository root:

```sh
./scripts/build-app.sh
open dist/UmamiBar.app
```

The application bundle is generated at `dist/UmamiBar.app`. Copy it to your Applications folder if desired. It runs in the menu bar without a Dock icon.

For a local development build using only the host architecture:

```sh
./scripts/build-app.sh native
```

The native-only build uses the toolchain's default deployment target. Use the default **universal** build when checking the explicit legacy deployment targets.

Builds are ad-hoc signed for local development. They are not Developer ID signed or notarized. GitHub Actions can publish release ZIPs; application self-updating is not implemented.

When rebuilding, quit the running app (Settings → 通用) before opening the new bundle. Replacing the file does not replace an already-running process.

## Connect Umami

1. On first launch the settings window opens automatically (later, use the gear button in the popover).
2. Under 连接, enter your service or API URL and API key, then click 验证并选择网站.
3. Under 网站, choose the websites to display.
4. Click 保存并查看; the popover then shows the overview.

Settings live in a regular window rather than the popover, so it stays open while you switch to a browser to copy the API key.

### Service URLs

| Deployment | Example | Behavior |
| --- | --- | --- |
| Umami Cloud | `https://api.umami.is/v1` | Uses the Cloud API base URL |
| Self-hosted, root deployment | `https://analytics.example.com` | Automatically adds `/api` |
| Self-hosted, subpath deployment | `https://example.com/analytics/api` | Uses the supplied path unchanged |
| Local development | `http://localhost:3000` | Adds `/api`; local HTTP is allowed |

For regional Cloud endpoints or custom proxies, supply the full API base URL. Nonempty URL paths are preserved, so include the complete API path for subpath deployments.

Only HTTPS is accepted for remote services. HTTP is permitted for `localhost`, `127.0.0.1`, and `::1`. URLs containing credentials, query strings, or fragments are rejected. Redirects are refused to avoid forwarding credentials to another endpoint.

The app supports **API keys**, not username/password login. Compatibility with older self-hosted Umami versions depends on their available authentication and endpoints. See the official [authentication guide](https://docs.umami.is/docs/api/authentication) and [Cloud API key guide](https://docs.umami.is/docs/cloud/api-key).

### Change a connection or website selection

- The gear button opens Settings on the General tab; choose Connection to edit credentials.
- Leave the API key field empty to reuse the saved key **only when the API base URL is unchanged**.
- “管理网站” in the overview footer opens the 网站 tab and lists websites for the current connection.
- The Websites tab groups pinned, followed and unfollowed websites. Changes save immediately after the initial connection has been committed. Click a color dot to change chart color, pin a website, or reorder within its group using the drag handle or Up/Down buttons. Unpinning restores its ordinary order.
- Removing a website from the selection does not delete it from Umami.
- One Umami instance is supported at a time.

### Language

UmamiBar is available in English and Simplified Chinese. Choose System, 简体中文 or English under Settings → General → Language; the change applies immediately. System follows your macOS language, and any language other than Chinese falls back to English. UI strings live in `Resources/<lang>.lproj/Localizable.strings`, keyed by the Chinese source text passed to `L("…")`; `tests-release/test_localization.py` fails if a string is missing a translation.

### Daily preferences

General settings provide Launch at Login, language, menu bar display, and local data controls. The login switch reflects the system registration, including an approval-required state; macOS 13+ uses Apple's [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice). macOS 10.15–12 uses an app-specific user LaunchAgent. Enabling it keeps the app in the menu bar without opening a window. Registration must be checked from an installed app; the rendering harness never enables login startup.

Last successful data is saved by default under `~/Library/Application Support/UmamiBar/successful-data.json`, separately for each service, website, period and timezone. A record contains a complete statistics/trend query and its original times, never the API key. Reopening restores matching results before a background refresh. Failed requests do not overwrite successful data; a missing range stays unavailable. Totals across mismatched query windows show “—”.

Open Saved Data to inspect retained ranges or clear them. Turning saving off asks for confirmation and clears stored statistics while keeping the connection and preferences. Already displayed live results can remain in memory. A source website that is unfollowed falls back to total visitors with a status message. Switching credentials clears saved results to avoid reusing another permission scope.

## Explore your websites

### Overview

Each website displays visitors, change from the preceding period, a mini session chart, pageviews, bounce rate, and average duration. Hover a chart for bucket values. Click the chart or website name to open details.

The menu bar can show total visitors, visitors for a specific followed website, or just the icon. Icon-only mode uses the system square size; AppKit sizes numeric modes to their contents. Total mode sums visitors across selected websites for the active range. Visitors are **not deduplicated across websites**. It is not a live online-user count. Large numbers use compact suffixes; the tooltip retains the exact count.

### Website details

Details retain the current time range and provide:

- Visitor totals and comparison with the preceding period.
- Pageviews, bounce rate, and average duration.
- A larger session chart.
- Switchable top pages and traffic sources, with up to five rows.
- Buttons to return to the overview or open the site's Umami dashboard.

The return button restores the overview's scroll position. Escape also returns from details when handled by the panel's responder chain. Loading and failure states are separate from empty results; failed detail requests offer a retry button.

### Time ranges and refresh

| Range | Window | Chart grouping |
| --- | --- | --- |
| Last 24 hours | Rolling 24 hours | Hourly |
| Last 7 days | Rolling 168 hours | Daily |
| Last month | One calendar month before the query end | Daily |

“Last month” is neither the current calendar month nor a fixed 30-day window. The system time zone is used for grouping and labels. Partial buckets at the boundaries are retained.

The popover checks for stale data when opened and refreshes on a 60-second timer while visible. Regular polling pauses while closed. Manual refresh shows a spinner and a completion timestamp. Authentication and rate-limit failures pause automatic retries; use settings or manual refresh to recover. Website requests currently run sequentially, so a larger selection can take longer to refresh.

## Data definitions

| Display | Source or calculation |
| --- | --- |
| Visitors | `visitors` from the stats endpoint; never calculated by adding chart buckets |
| Session trend | `sessions` from the pageviews endpoint; not a unique-visitor trend |
| Pageviews | `pageviews` from the stats endpoint |
| Bounce rate | `bounces / visits × 100` |
| Average duration | `totaltime / (visits - bounces)`, in seconds |
| Visitor change | Current visitors versus a separate query for the preceding interval of equal length |
| Breakdown percentages | Each row's count divided by the sum of the returned top five rows |

Missing fields or undefined denominators display `—`. A previous count of zero produces “New” or “Unchanged”, rather than an invalid percentage. A failed comparison query displays an unavailable comparison.

Successful time-series responses are expanded into complete time buckets; missing buckets become zero. The app handles Umami timezone-grouped SQL labels that serialize local wall-clock values with a `Z` suffix. Nonzero points entirely outside the requested range produce an error instead of a misleading empty chart. Backend timestamp conventions still need verification for other deployments.

Top-page and source counts follow the API's dimension semantics. The UI labels them as counts; top-five percentages are **not whole-site percentages**. Empty source results are displayed as empty results, not fabricated direct-traffic rows.

API references: [summary statistics](https://docs.umami.is/docs/api-reference/get-website-stats), [time series](https://docs.umami.is/docs/api-reference/get-website-pageviews), [ranked metrics](https://docs.umami.is/docs/api-reference/get-website-metrics).

## Development and checks

Run the test suite:

```sh
swift test --disable-sandbox \
  --scratch-path /tmp/umamibar-build \
  -Xswiftc -module-cache-path -Xswiftc /tmp/umamibar-module-cache
```

The tests cover URL validation, current and legacy stats responses, missing values, comparison calculations, month boundaries, sparse time series, and timezone-grouped labels. The temporary build paths avoid requiring access to user-level compiler caches. `--disable-sandbox` disables SwiftPM's build sandbox for this local build; it does not change application permissions.

For native rendering checks with sample data, compile the standalone harness:

```sh
xcrun swiftc -parse-as-library \
  -module-cache-path /tmp/umamibar-module-cache \
  Sources/UmamiBar/Models.swift \
  Sources/UmamiBar/ChartView.swift \
  Sources/UmamiBar/Components.swift \
  Sources/UmamiBar/NativePanel.swift \
  Sources/UmamiBar/API.swift \
  Sources/UmamiBar/SettingsWindow.swift \
  Sources/UmamiBar/SettingsViews.swift \
  Sources/UmamiBar/Preferences.swift \
  Sources/UmamiBar/SnapshotStore.swift \
  Sources/UmamiBar/LoginLaunch.swift \
  scripts/visual-check.swift \
  -o /tmp/umamibar-native-check

/tmp/umamibar-native-check dark detail
/tmp/umamibar-native-check light empty
/tmp/umamibar-native-check dark settings-general
/tmp/umamibar-native-check dark detail --navigation-tests
```

For the isolated preference flow, start `python3 scripts/mock-api.py --port 8768`, then run `/tmp/umamibar-native-check light settings-websites --mock=http://127.0.0.1:8768 --preferences-tests`. Add `--language-test` when running from a test bundle containing the localization resources. `--cached --pinned` previews restored overview data. The harness uses isolated preferences and a temporary snapshot directory; login startup is never enabled by tests.

The harness requires a graphical macOS session. It writes PNG previews to `/tmp/native-<appearance>-<screen>.png`. Screens include `overview`, `detail`, `empty`, `settings-connection`, `settings-websites`, and `settings-general`. Setting `UMAMIBAR_MOCK=http://127.0.0.1:PORT` (a local server answering `GET /api/websites` for key `test-key`) drives the real verify → website list flow first; add `--save-test` to also check saving. `--navigation-tests` checks native action dispatch; it is not a full end-to-end network test.

An explicit `--diagnose-series` or `--diagnose-details` argument on the app executable performs read-only checks using the saved connection. These modes can access Keychain and contact your Umami server. They print counts and diagnostic status without printing keys, service URLs, website IDs, or page paths. Series diagnostics also print returned timestamps. They are optional debugging tools, not part of normal startup.

## Project structure

```text
Sources/UmamiBar/
  App.swift          App lifecycle, menu bar, state and request coordination
  Components.swift   Shared painted design system: colors, surface, buttons, inputs
  NativePanel.swift  Popover screens: empty state, overview and details
  SettingsWindow.swift Settings tabs and immediate persistence
  SettingsViews.swift  Native form rows and draggable website controls
  Preferences.swift    Menu display and connection-scoped website order
  SnapshotStore.swift  Atomic, scoped successful-result persistence
  LoginLaunch.swift    System login registration and older-macOS fallback
  ChartView.swift    Chart drawing, hover values and keyboard interactions
  API.swift          HTTP requests, authentication and website pagination
  Models.swift       API models, periods, metrics and URL normalization
  TimeBuckets.swift  Sparse-series expansion and timestamp handling
  Keychain.swift     Credential storage
  Diagnostics.swift Optional read-only API diagnostics
Tests/UmamiBarTests/  Core regression tests
scripts/             App packaging, icon generation and rendering checks
assets/              App icon master, iconset and ICNS
index.html           Interactive design prototype with sample data
PRD.md               Requirements and accepted changes
```

To view the prototype independently:

```sh
python3 -m http.server 8765 --bind 127.0.0.1
```

Open [the local prototype](http://127.0.0.1:8765/). Its connection form does not save or transmit API keys. The native app does not depend on this server.

## Troubleshooting and current limits

- **No menu bar icon after rebuilding:** quit the old process, then reopen the generated `.app`.
- **Connection rejected:** check the full API base URL, key permissions, and server API compatibility. Redirecting URLs must be replaced with their final destination.
- **A number is present but its chart fails:** totals and trends use separate endpoints; check the error message and time-series compatibility. The app retains available data on partial failures.
- **No traffic sources:** the endpoint may legitimately return no rows for the selected period.
- **A team website is missing:** discovery uses the websites endpoint; team visibility depends on the server's returned permissions and list.
- **Old macOS compatibility:** Intel deployment metadata is verified as 10.15, but startup, Keychain, appearance, and rendering still require Catalina hardware validation.
- **Distribution:** Release builds support Developer ID signing, notarization and Sparkle updates. Local builds are ad-hoc signed. Actual login startup and Catalina behavior still need installed-app/hardware validation.

See [PRD.md](PRD.md) for the requirements history. Checked-in images under `docs/previews/` are sample-data snapshots and may lag small visual changes.

## GitHub Topics

Suggested repository topics:

[`umami`](https://github.com/topics/umami) · [`macos`](https://github.com/topics/macos) · [`menu-bar`](https://github.com/topics/menu-bar) · [`swift`](https://github.com/topics/swift) · [`appkit`](https://github.com/topics/appkit) · [`analytics`](https://github.com/topics/analytics) · [`privacy`](https://github.com/topics/privacy) · [`macos-app`](https://github.com/topics/macos-app)

## License

[MIT](LICENSE) © 2026 helson-lin
