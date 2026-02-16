#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MACOS_DIR="$SCRIPT_DIR/../../app/DerivedData/Ficino/Build/Products/Debug/MusicContextGenerator.app/Contents/MacOS"
export ORIGINAL_PWD="$PWD"
cd "$MACOS_DIR" && exec ./MusicContextGenerator "$@"
