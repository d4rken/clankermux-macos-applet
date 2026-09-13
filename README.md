# Clankermux Usage for macOS

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

A native macOS menu bar app for monitoring a
[Clankermux](https://github.com/d4rken/clankermux) proxy. The workload pace bars
follow the [Linux Mint applet](https://github.com/d4rken/clankermux-mint-applet),
using the current public workload API introduced in Clankermux 2026.9.36.

The menu bar shows one of two forms:

```text
C [ cut | add ]        stacked pace bars
GPT 62%  Claude 48%    weekly usage
```

**Stacked pace bars** is the narrower form: up to three bars
stacked vertically with a workload initial beside each, using 52 points for
three workloads. Additional workloads start another stack. Bars extend left for
a reduction in consumption and right for an increase, each half representing a
50% change. These are pace estimates from the server, not remaining quota
percentages or a suggested number of agents. **Stale** and **Expired** stay
visible as text.

**Weekly usage** is the default. It draws a provider mark and the weekly
percentage for each workload, averaged across that provider's accounts with
equal weight per account. Accounts without a readable percentage are left out of the average
rather than counted as zero, and a `*` marks a partial or cached reading.
Paused accounts still count, because their quota is still spent. macOS may hide
a status item that does not fit the menu bar, and this form needs roughly 180
points for three workloads.

Full names, coverage, reset checkpoints and the caveats are in the tooltip in
both forms.

The popup uses a 620-point-wide layout: one workload summary line each, with
availability counts on the right, then account forecasts beside their usage
bars. Paused accounts show only their heading and status, without quota bars or
forecasts. A provider whose accounts are all paused drops out of the menu bar
and out of the popup's summary lines, but keeps its account entries. It returns
after an account resumes; rate-limited or exhausted accounts remain visible.

Click the item for:

- one line per workload: weekly outlook, pace estimate, exhaustion estimate, and coverage
- how many accounts can serve a request right now, independently of weekly budget
- per-account availability, credentials, usage bars, and window forecasts
- cached readings and failed-feed notices
- refresh, dashboard, settings, and quit actions

## Reading the pace bars

Green indicates an estimated increase fits; orange indicates a reduction.
A fully modeled, supported exhausted weekly budget is red. Missing, stale,
expired, or unsupported advice is neutral.

A positive estimate is the last tested passing increase. **≥+50%** means the
largest tested increase fits, not that 50% is an exact maximum. **−50% insufficient**
means the tested cut did not suffice; it is not a recommended reduction.

Family figures are conservative bounds. Fable overlaps Claude, so their
capacities and percentages must not be added. Partial forecasts describe the
modeled subset and withhold numeric pace advice. Idle accounts may still serve
requests even though they have no burn evidence for forecasting.

Weekly budget and availability have different denominators. Paid fallback may
be available after subscription quota is exhausted, and 5-hour limits can
interrupt work independently. Availability describes a fresh, unpinned,
nominal-sized request. The forecast assumes the current distribution of burn
across accounts; it does not redistribute demand after an account exhausts.

## Install

Requires macOS 13 or newer and a Swift 6.1 toolchain.

```sh
make install
```

This builds and signs `Clankermux Usage.app` ad-hoc and copies it to
`~/Applications`. Launch it from there. The app lives entirely in the menu bar.

To build the bundle without installing it:

```sh
make app
```

The default server is `http://127.0.0.1:8080`. Use **Settings…** to enter
another HTTP or HTTPS URL, hostname, or IP address. The address applies when you
press Return or leave the field. Settings flags an address the app cannot use
before you leave the field, and reports what the last poll found under it.

## API and refresh behavior

The app uses three unauthenticated, read-only endpoints:

- `GET /public/v1/status`
- `GET /public/v1/accounts`
- `GET /public/v1/workloads`

Accounts and status follow the configured interval, defaulting to 30 seconds.
Workloads refresh independently every 15 seconds. The server caches availability
for about five seconds and weekly calculations for about sixty seconds.
Failed workload requests back off from 30 seconds to a five-minute cap.
Manual refresh bypasses backoff.

Countdowns update every second. A newly expired weekly checkpoint requests a
fresh snapshot; the app never advances a deadline or assumes quota recovered.
Repeated copies of the same expired calculation do not trigger a request loop.

Weekly and availability freshness use their own `computedAt` fields,
not the envelope timestamp or the time a response arrived. Readings become
stale after three minutes, on a failed fetch, or when their computation
timestamp is missing. Cached readings stay in the popover, clearly marked.
The oldest usage observation is shown separately from computation age.

Weekly usage staleness is judged against the `/accounts` reply's own
`generatedAt`, advanced by the time since it arrived, so a client clock skewed
against the server's does not mark fresh readings cached.

This version replaces the retired runway, pacing, and headroom feeds.
It requires the current workload contract; it does not fall back to
quota averages or removed endpoints. Saved “Runway”, “Icon only” and
“Full-size pace bars” modes fall back to the current default; the retired
pace-bar width and percentage settings are removed.

Account names are public in this API. Credentials, prompts, and response bodies
are not exposed. The app performs no server writes.

The bundle permits arbitrary HTTP hosts using `NSAllowsArbitraryLoads`.
Use HTTPS when traffic leaves your machine.

## Settings

| Setting | Default | Range |
| --- | --- | --- |
| Server URL | `http://127.0.0.1:8080` | |
| Refresh accounts and status | 30 seconds | 10 to 900, in steps of 10 |
| Request timeout | 8 seconds | 2 to 60 |
| Menu bar shows | Weekly usage | Stacked pace bars, Weekly usage |
| Show model-family indicators and utilization bars | on | |

## Development

No third-party dependencies are required.

```sh
make check test
```

The Foundation-only core handles API decoding, presentation rules, and refresh
coordination. AppKit draws the menu bar; SwiftUI renders the popover and settings.
Tests cover the proxy's published JSON examples, freshness and deadline behavior,
retry scheduling, partial request failures, and offscreen UI layout.

## Provider marks

The OpenAI and Anthropic marks come from the Linux Mint applet, which took them
from the Clankermux dashboard's `provider-marks.tsx`, sourced there from Simple
Icons (CC0-1.0). Brand marks remain trademarks of their respective owners. The
Fable F monogram is a local identifier, not an official brand mark. The same
notice ships inside the app bundle as `ProviderMarks-ATTRIBUTION.md`.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
