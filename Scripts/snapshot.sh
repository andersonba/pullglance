#!/bin/bash
# Renders the popover and the Settings tabs to PNG files. Usage: Scripts/snapshot.sh [dir] [--demo]
# --demo uses fictional data and also writes hero.png, the README image.
set -e
cd "$(dirname "$0")/.."
swift build 2>&1 | grep -E "error|warning: unre" || true
.build/debug/Pullglance --snapshot "$@"
