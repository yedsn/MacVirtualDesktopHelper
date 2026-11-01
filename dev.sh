#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="MacVirtualDesktopHelper"

# Stop only this project's built app. Do not match source editors or other apps.
if pgrep -f "$SCRIPT_DIR/.build/MacVirtualDesktopHelper.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
  pkill -TERM -f "$SCRIPT_DIR/.build/MacVirtualDesktopHelper.app/Contents/MacOS/$APP_NAME" || true
  for _ in {1..20}; do
    pgrep -f "$SCRIPT_DIR/.build/MacVirtualDesktopHelper.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1 || break
    sleep 0.1
  done
  if pgrep -f "$SCRIPT_DIR/.build/MacVirtualDesktopHelper.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    pkill -KILL -f "$SCRIPT_DIR/.build/MacVirtualDesktopHelper.app/Contents/MacOS/$APP_NAME" || true
  fi
fi

exec "$SCRIPT_DIR/run.sh" --show-overview "$@"
