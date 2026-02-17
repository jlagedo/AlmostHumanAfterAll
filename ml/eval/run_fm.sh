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

OUTPUT="$DATA/eval_output/output_${VERSION}_$(date +%Y%m%d_%H%M%S).jsonl"
mkdir -p "$(dirname "$OUTPUT")"

PROMPTS="$DATA/../prompts"

"$APP" "$DATA/eval_output/prompts_top100.jsonl" "$PROMPTS/fm_instruction_v14.json" "$OUTPUT" "$@"
