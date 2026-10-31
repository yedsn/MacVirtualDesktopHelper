#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_PATH="$("$SCRIPT_DIR/build.sh" | tail -n 1)"
open -n "$APP_PATH" --args "$@"
