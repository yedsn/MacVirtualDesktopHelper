#!/bin/zsh
# Build distributable artifacts, install locally, and launch the installed app.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="MacVirtualDesktopHelper"
APP_PATH="/Applications/$APP_NAME.app"
ARCH="$(uname -m)"

"$ROOT_DIR/scripts/release/package.sh" "$ARCH"
SOURCE_APP="$ROOT_DIR/.build/$ARCH/$APP_NAME.app"
codesign --verify --deep --strict "$SOURCE_APP"

# Stop only the installed copy and copies built by this checkout.
for app_pid in $(pgrep -x "$APP_NAME" || true); do
  executable="$(ps -p "$app_pid" -o comm=)"
  if [[ "$executable" != "$APP_PATH/Contents/MacOS/$APP_NAME" &&
        "$executable" != "$ROOT_DIR/.build/"*"/$APP_NAME.app/Contents/MacOS/$APP_NAME" &&
        "$executable" != "$ROOT_DIR/.build/$APP_NAME.app/Contents/MacOS/$APP_NAME" ]]; then
    continue
  fi
  kill -TERM "$app_pid"
  for _ in {1..50}; do
    kill -0 "$app_pid" 2>/dev/null || break
    sleep 0.1
  done
  if kill -0 "$app_pid" 2>/dev/null; then
    echo "应用尚未退出，停止部署：PID $app_pid" >&2
    exit 1
  fi
done

if [[ -d "$APP_PATH" ]]; then
  BACKUP_DIR="$(mktemp -d /tmp/mvdh-local-deploy.XXXXXX)"
  ditto "$APP_PATH" "$BACKUP_DIR/$APP_NAME.app"
  echo "旧版备份：$BACKUP_DIR/$APP_NAME.app"
fi
ditto "$SOURCE_APP" "$APP_PATH"
codesign --verify --deep --strict "$APP_PATH"
open "$APP_PATH" --args --show-overview
echo "已部署并启动：$APP_PATH"
echo "安装包目录：$ROOT_DIR/dist"
