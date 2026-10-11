#!/bin/bash
# Renders the popover and the Settings tabs to PNG files, using the real gh data. Usage: Scripts/snapshot.sh [dir]
set -e
cd "$(dirname "$0")/.."
swift build 2>&1 | grep -E "error|warning: unre" || true
.build/debug/Pullglance --snapshot ${1:+"$1"}
