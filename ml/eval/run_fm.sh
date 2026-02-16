#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

APP="../../app/DerivedData/Ficino/Build/Products/Debug/FMPromptRunner.app/Contents/MacOS/FMPromptRunner"

if [ ! -x "$APP" ]; then
    echo "Error: FMPromptRunner not built. Build it in Xcode first."
    exit 1
fi

DATA="$(pwd)/../data"

OUTPUT="$DATA/eval_output/output_$(date +%Y%m%d_%H%M%S).jsonl"
mkdir -p "$(dirname "$OUTPUT")"

PROMPTS="$DATA/../prompts"

"$APP" "$DATA/eval_output/prompts_top100.jsonl" "$PROMPTS/fm_instruction_v1.txt" "$OUTPUT" "$@"
