#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -z "${1:-}" ]; then
    echo "Usage: run_fm.sh <version-tag> [extra args...]"
    echo "  e.g. run_fm.sh v19"
    exit 1
fi
VERSION="$1"; shift

APP="../../app/DerivedData/Ficino/Build/Products/Debug/FMPromptRunner.app/Contents/MacOS/FMPromptRunner"

if [ ! -x "$APP" ]; then
    echo "Error: FMPromptRunner not built. Build it in Xcode first."
    exit 1
fi

DATA="$(pwd)/../data"

OUTPUT="$DATA/eval/output_${VERSION}_$(date +%Y%m%d_%H%M%S).jsonl"
mkdir -p "$(dirname "$OUTPUT")"

PROMPTS="$DATA/../prompts"
INSTRUCTION="$PROMPTS/fm_instruction_${VERSION}.json"

if [ ! -f "$INSTRUCTION" ]; then
    echo "Error: $INSTRUCTION not found."
    exit 1
fi

"$APP" "$DATA/eval/prompts_top100.jsonl" "$INSTRUCTION" "$OUTPUT" "$@"
