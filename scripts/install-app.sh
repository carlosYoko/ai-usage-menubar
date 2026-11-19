#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="AI Usage Menubar.app"
SOURCE="$ROOT/dist/$APP_NAME"
DEST="$HOME/Applications/$APP_NAME"

"$ROOT/scripts/build-app.sh" release
mkdir -p "$HOME/Applications"
rm -rf "$DEST"
ditto "$SOURCE" "$DEST"
open "$DEST"
printf 'Installed and opened: %s\n' "$DEST"
