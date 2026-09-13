# Clankermux Usage for macOS

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)

A native macOS menu bar app for monitoring the accounts behind a
[Clankermux](https://github.com/d4rken/clankermux) proxy.

The menu bar shows one mark per provider with its weekly usage, the
equal-weight average of that provider's readable account percentages:

```text
[OpenAI] 50%   [Anthropic] 30%   [F] 95%
```

`*` marks a partial or cached reading. Settings switches the menu bar to
stacked pace bars, the server's suggested change in consumption until the next
weekly reset. Click the item for per-workload forecasts and per-account usage.

## Install

Requires macOS 13 or newer.

Download the zip from the
[latest release](https://github.com/d4rken/clankermux-macos-applet/releases/latest),
unzip it, and move `Clankermux Usage.app` into `~/Applications`. The app lives
entirely in the menu bar and has no Dock icon.

The bundle is ad-hoc signed rather than notarized, so macOS refuses it on first
launch. Right-click the app, choose **Open**, and confirm at the prompt. Once is
enough. The terminal equivalent:

```sh
xattr -dr com.apple.quarantine ~/Applications/"Clankermux Usage.app"
```

To build it yourself instead, with a Swift 6.1 toolchain:

```sh
make install
```

The default server is `http://127.0.0.1:8080`. Open **Settings…** from the
popover for a different hostname, IP address, or complete HTTP/HTTPS URL.

## API

Unauthenticated and read-only, requiring Clankermux **2026.9.36 or newer**:

- `GET /public/v1/status`
- `GET /public/v1/accounts`
- `GET /public/v1/workloads`

Account names are public. Credentials, prompts and response bodies are not
exposed, and the app performs no server writes.

## License

Licensed under the [GNU General Public License v3.0](LICENSE).
