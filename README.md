# Clankermux Usage for macOS

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

A native macOS menu bar app for monitoring a
[Clankermux](https://github.com/d4rken/clankermux) proxy. The workload pace bars
follow the [Linux Mint applet](https://github.com/d4rken/clankermux-mint-applet),
using the current public workload API introduced in Clankermux 2026.9.36.

The menu bar can show an icon, compact pace bars, or full-size directional workload bars:

```text
Claude [ cut | add ]  GPT [ cut | add ]  Fable [ cut | add ]
```

Bars extend left for a reduction in consumption and right for an increase.
Each half represents a 50% change. These are pace estimates from the server,
not remaining quota percentages or a suggested number of agents.

The icon remains the default because macOS may hide status items that do not
fit the menu bar. **Compact pace bars** stack up to three bars vertically,
with a workload initial beside each bar, using 52 points for three workloads.
Additional workloads start another stack. Full names remain in the tooltip
and popup. **Full-size pace bars** use the
Linux-style label-and-bar layout. Exact percentages are optional in full-size
mode; the tooltip and popover always show them. **Stale** and **Expired** remain
visible in both bar modes.

The popup uses a 620-point-wide layout with workload outlook and pacing on one
row, availability and coverage on the next, and account forecasts beside their
usage bars. Click a workload's chevron to expand its forecast details.
Paused accounts show only their heading and status, without quota bars or forecasts.
Menu-bar workloads are hidden when all accounts for their provider are paused.
They reappear after an account resumes; rate-limited or exhausted accounts remain visible.

Click the item for:

- workload weekly outlook, pace estimates, and the next reset checkpoint
- current availability, independently of weekly subscription budget
- modeled, idle, learning, and unreadable forecast coverage
- account risk counts and conservative family bounds
- per-account availability, credentials, usage bars, and window forecasts
- computation and evidence ages, cached readings, and failed-feed notices
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
another HTTP or HTTPS URL, hostname, or IP address. The URL applies when you
press Return or leave the field.

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

This version replaces the retired runway, pacing, and headroom feeds.
It requires the current workload contract; it does not fall back to
quota averages or removed endpoints. Saved “Runway” mode becomes “Compact pace bars”;
the retired runway-warning and default-routing-candidate settings are removed.

Account names are public in this API. Credentials, prompts, and response bodies
are not exposed. The app performs no server writes.

The bundle permits arbitrary HTTP hosts using `NSAllowsArbitraryLoads`.
Use HTTPS when traffic leaves your machine.

## Settings

| Setting | Default | Range |
| --- | --- | --- |
| Server URL | `http://127.0.0.1:8080` | |
| Refresh accounts/status | 30 seconds | 10 to 900, in steps of 10 |
| Request timeout | 8 seconds | 2 to 60 |
| Menu bar shows | Icon only | Icon, Compact pace bars, Full-size pace bars |
| Width of each full-size pace bar | 52 points | 30 to 100, in steps of 2 |
| Show percentages beside full-size bars | off | |
| Show model-specific limits | on | |

Existing saved percentage preferences are preserved.

## Development

No third-party dependencies are required.

```sh
make check test
```

The Foundation-only core handles API decoding, presentation rules, and refresh
coordination. AppKit draws the menu bar; SwiftUI renders the popover and settings.
Tests cover the proxy's published JSON examples, freshness and deadline behavior,
retry scheduling, partial request failures, and offscreen UI layout.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
