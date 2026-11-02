#!/bin/bash
# Builds "KhaiCleanMac Dev.app" into ./build: a debug build for Apple silicon (or KHAI_ARCH) with its own
# bundle ID (id.rizkyraf.KhaiCleanMac.dev) and name. It runs next to the installed KhaiCleanMac without
# touching its settings, history, Keychain item or Full Disk Access grant, and never offers app updates.
# Usage: scripts/build-dev-app.sh [--open]   (--open quits a running dev build and starts the new one)
set -euo pipefail

cd "$(dirname "$0")/.."
KHAI_FLAVOR=dev KHAI_ARCH="${KHAI_ARCH:-$(uname -m)}" ./scripts/build-app.sh

if [[ "${1:-}" == "--open" ]]; then
    osascript -e 'tell application id "id.rizkyraf.KhaiCleanMac.dev" to quit' >/dev/null 2>&1 || true
    open "build/KhaiCleanMac Dev.app"
fi
