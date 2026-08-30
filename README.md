# Clankermux Usage for macOS

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

A native macOS menu bar app for monitoring the accounts behind a
[Clankermux](https://github.com/d4rken/clankermux) proxy. It is a behavioural port of the
[Cinnamon panel applet](https://github.com/d4rken/clankermux-mint-applet): same data sources, same
panel content, same popup detail, same settings and defaults.

The menu bar shows a gauge tinted by state, green above the configured runway warning duration,
orange below it, and red when the pool is out of quota or nothing is routable. Under Settings the
item can instead show Clankermux's projected quota runway:

```text
R 5d 18h
```

or the runway followed by server-computed mean utilization for the 5-hour, 7-day and
model-specific quota pools:

```text
R 5d 18h  5h [  5%]  7d [ 49%]  Fable [ 67%]
```

The icon is about 24 points wide, the runway about 106, and the full panel about 435. macOS gives a
status item no room it has not got and draws nothing at all rather than truncating, so on a busy
menu bar the wider forms can vanish entirely, which is why the icon is the default. Whichever form
is showing, the tooltip and the popover carry the full detail.

When availability is degraded, the default-context account count appears as an exception beside the
runway, for example `R 18h · 3/4!`. It stays out of the normal display because runway describes
quota capacity while availability also includes pauses, cooldowns, credentials, and provider
overloads.

When the meters are switched on, unused model-specific quota families are omitted from the menu bar
to conserve space, but remain available in the popover. Core 5-hour and 7-day meters remain visible
at 0%.

Each percentage is the unweighted mean reported by Clankermux across accounts that supplied that
window. The popover shows contributor and unknown-account counts so a partial mean cannot pass as
full coverage. Click the item for:

- projected quota runway, model horizon, API-key coverage, and the account/window causing run-out
- 5-hour and 7-day usage bars for every account
- model-specific weekly limits such as Fable
- per-window forecasts and reset countdowns where Clankermux has sufficient evidence
- the default candidate for a fresh, unpinned, nominal-sized request
- availability, credential, provider-overload, and measurement-freshness state
- the last successful refresh time, so stale data is easy to spot
- manual refresh, a shortcut to the Clankermux dashboard, settings, and quit

When Clankermux observes an upstream provider overload, the menu bar item gains an hourglass. The
popover distinguishes provider-wide and model-scoped breakers, including open and half-open recovery
states.

The runway is green above the configured warning duration, orange below it, and red when the pool is
out of quota. Incomplete API-key coverage adds `*` and is always warning-colored: an unobserved key
could have less runway than the stated projection. `>14d` means no run-out was found inside the
server's 14-day modelling horizon; it never claims infinity.

Usage bars turn orange at 80% and red at 100%. Individual forecast confidence remains visible in the
popover; low-confidence exhaustion is never colored as certain.

## Install

Requires macOS 13 or newer and a Swift 6.1 toolchain (Xcode or the Command Line Tools).

```sh
make install
```

That builds `Clankermux Usage.app`, signs it ad-hoc, and copies it into `~/Applications`. Launch it
from there. The app has no Dock icon and no application menu: it lives entirely in the menu bar.

To build the bundle without installing it:

```sh
make app
```

The default server is a Clankermux instance on the same machine:

```text
http://127.0.0.1:8080
```

Click the menu bar item and choose **Settings…** to enter a different hostname, IP address, or
complete HTTP/HTTPS URL. The server URL applies when you press Return or leave the field, so a
half-typed hostname is never polled. The settings window also controls the polling interval, request
timeout, the menu bar meters, runway warning duration, and scoped-limit visibility.

## API and security

The app uses Clankermux's unauthenticated, read-only public widget API:

- `GET /public/v1/status`
- `GET /public/v1/accounts`
- `GET /public/v1/runway`

Status and accounts follow the configured refresh interval, which defaults to 30 seconds. The more
expensive runway projection is cached and refreshed at most every five minutes, or immediately with
**Refresh now**. These endpoints contain no personal identities, credential material, API-key
metadata, or write access.

The bundle sets `NSAllowsArbitraryLoads`. App Transport Security lets a private-range IP literal or a
`.local` name load over plain HTTP without any exemption, but it blocks a qualified DNS hostname over
HTTP, and `NSAllowsLocalNetworking` does not lift that. Since the applet this ports supports
arbitrary HTTP hosts, arbitrary loads is what preserves it. Point the app at HTTPS if the traffic
leaves your machine.

## Settings

| Setting | Default | Range |
| --- | --- | --- |
| Server URL | `http://127.0.0.1:8080` | |
| Refresh every | 30 seconds | 10 to 900, in steps of 10 |
| Request timeout | 8 seconds | 2 to 60 |
| Menu bar shows | Icon only | Icon only, Runway, or Runway and pool meters |
| Width of each menu bar progress bar | 52 points | 30 to 100, in steps of 2 |
| Show percentages beside menu bar bars | on | |
| Warn when quota runway falls below | 72 hours | 1 to 336 |
| Show model-specific limits | on | |
| Put the default routing candidate first | on | |

## Development

No third-party dependencies are required.

```sh
make check test
```

`ClankermuxCore` holds the entire domain layer and imports Foundation only, which keeps every rule
runnable in a headless test process. `ClankermuxUsage` holds the AppKit and SwiftUI layer.

## Differences from the Cinnamon applet

Behaviour is otherwise identical. All but the last of these are deliberate:

1. **The polling-source watchdog is not ported.** Its defences are specific to GJS: a thrown poll
   callback permanently killing a repeating GLib source, and timer sources disappearing out from
   under the applet. A main-queue `DispatchSourceTimer` owned by the app delegate has no external
   remover and its handler cannot throw, so both failure modes are structurally absent. The
   per-refresh request timeout is ported and behaves the same.
2. **There is a Quit command.** Cinnamon removes an applet from the panel; an agent app with no Dock
   icon needs its own way out.
3. **Menu bar bars are drawn in a custom `NSView`** hosted by the status bar button, rather than St
   widgets with a CSS stylesheet.
4. **Severity colours come from the system palette** rather than the stylesheet's fixed hexes. The
   green, orange and red meanings are preserved, and the colours adapt to light and dark menu bars.
5. **Settings are a hand-built SwiftUI form**, since there is no `settings-schema.json` runtime. The
   keys, defaults and ranges are identical.
6. **The version starts at 1.0.0.** This is a new product with its own history, not a continuation of
   the applet's version line.
7. **The bundle identifier is `eu.darken.clankermux-usage`.**
8. **An explicit `null` for `pool.configured` or `pool.defaultRoutable` is treated as missing.** The
   applet renders 0 there, because JavaScript coerces `null` to `0` before its finiteness check.
   That is a coercion accident rather than intent, so this port falls back to the derived account
   count instead.
9. **`NSAllowsArbitraryLoads` is set**, as described above.
10. **A non-2xx response always reports its HTTP status and reason.** The applet parses the body
    before it checks the status, so an error page that is not JSON reports a JSON parse error
    instead of the status line. This port checks the status first and only decodes a 2xx body.
11. **The menu bar shows an icon by default, not the panel.** A Cinnamon panel has room for the
    runway and every pool meter side by side. The same content is about 435 points wide, and a
    macOS menu bar holding a normal set of status items may have as little as 20 points to spare,
    with macOS drawing nothing at all rather than truncating. The runway and the full panel are
    therefore opt-in, and the tooltip and popover always carry the detail.
12. **Releasing a click away from the menu bar item can swallow the next click.** Pressing the item
    while the popover is open and then letting go somewhere else leaves the following click on the
    item without effect, and a second click opens it again. This is a known limitation of this
    version rather than intended behaviour.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
