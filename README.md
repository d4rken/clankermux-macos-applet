# Clankermux Usage for macOS

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

A native macOS menu bar app for monitoring the accounts behind a
[Clankermux](https://github.com/d4rken/clankermux) proxy.

The menu bar defaults to combined weekly usage, one mark per provider:

```text
[OpenAI] 50%   [Anthropic] 30%   [F] 95%
```

Each value is the average of that provider's readable weekly account
percentages, with equal weight per account, including paused accounts. Fable
uses its own weekly limits. These are account averages, not capacity-weighted
totals; the API does not publish quota sizes. Missing readings are excluded
rather than counted as zero. `*` marks a partial or cached reading, and the
tooltip says how many accounts are included.

Choose **Settings > Menu bar > Stacked pace bars** for the narrower form:

```text
C [ cut | add ]
G [ cut | add ]
F [ cut | add ]
```

Up to three bars stack vertically with a workload initial beside each, using 52
points for three workloads; more workloads start another stack. Bars extend left
for a reduction in consumption and right for an increase, each half representing
a 50% change. These are pace estimates from the server until the next weekly
reset, not remaining quota and not a suggested number of agents. **≥+50%** means
the largest tested increase fits, not that 50% is an exact maximum. **Stale** and
**Expired** stay visible as text.

Fable overlaps Claude, so their capacities and percentages must not be added.
Partial forecasts describe only the modeled subset and withhold numeric advice.
A provider whose accounts are all paused drops out of the menu bar and out of
the popover's summary, but keeps its account entries.

Click the item for one summary line per workload, weekly budget shown separately
from how many accounts can serve a request right now, then per-account
availability, credentials, usage bars and window forecasts. Weekly risk can
coexist with available paid fallback. Availability describes a fresh, unpinned,
nominal-size request and is not a guarantee for restricted API keys. Coverage,
reset checkpoints and evidence ages are in the tooltip.

## Install

Requires macOS 13 or newer.

Download the zip from the [latest release](https://github.com/d4rken/clankermux-macos-applet/releases/latest),
unzip it, and move `Clankermux Usage.app` into `~/Applications`. The app lives
entirely in the menu bar and has no Dock icon.

The bundle is ad-hoc signed rather than notarized, so macOS refuses it on first
launch. Right-click the app, choose **Open**, and confirm at the prompt. Doing
this once is enough. The equivalent from a terminal:

```sh
xattr -dr com.apple.quarantine ~/Applications/"Clankermux Usage.app"
```

To build it yourself instead, with a Swift 6.1 toolchain:

```sh
make install
```

The default server is a Clankermux instance on the same machine:

```text
http://127.0.0.1:8080
```

Open **Settings…** from the popover to enter a different hostname, IP address,
or complete HTTP/HTTPS URL. It reports what the last poll found, and flags an
address the app cannot use before you leave the field. The address applies when
you press Return or leave the field. Settings also controls the polling
interval, request timeout, menu bar form, and model-family visibility.

## API and security

The app uses Clankermux's unauthenticated, read-only public widget API, and
requires the replacement contract from **2026.9.36 or newer**:

- `GET /public/v1/status`
- `GET /public/v1/accounts`
- `GET /public/v1/workloads`

Accounts and status follow the configured interval, 30 seconds by default.
Workloads poll independently every 15 seconds, backing off from 30 seconds to a
five-minute cap after a failure. Manual refresh bypasses backoff. A newly
expired weekly checkpoint requests a fresh snapshot; the app never advances a
deadline or assumes quota recovered.

Weekly budgets and availability carry separate `computedAt` timestamps. Readings
become stale after three minutes, on a failed fetch, or when their computation
timestamp is missing, and cached readings stay visible clearly marked. Weekly
usage staleness is judged against the `/accounts` reply's own `generatedAt`, so
a client clock skewed against the server's does not mark fresh readings cached.

Account names are public in this API. Credentials, prompts and response bodies
are not exposed, and the app performs no server writes. The bundle permits
plain HTTP using `NSAllowsArbitraryLoads`; use HTTPS when traffic leaves your
machine.

## Development

No third-party dependencies are required. Run the checks with:

```sh
make check test
```

The Foundation-only core handles API decoding, presentation rules and refresh
coordination. AppKit draws the menu bar; SwiftUI renders the popover and
settings. Setting `CLANKERMUX_PREVIEW_DIR` exports the offscreen UI tests as
PNGs for visual inspection.

The OpenAI and Anthropic marks come from the
[Cinnamon applet](https://github.com/d4rken/clankermux-mint-applet), which took
them from the Clankermux dashboard, sourced there from Simple Icons (CC0-1.0).
Brand marks remain trademarks of their respective owners. The Fable F monogram
is a local identifier, not an official brand mark.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
