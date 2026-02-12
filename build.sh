#!/bin/bash
set -e

cd "$(dirname "$0")"

pkill -9 Ficino 2>/dev/null || true
sleep 0.5

xcodebuild -project Ficino.xcodeproj \
  -scheme Ficino \
  -derivedDataPath ./build \
  build 2>&1 | tail -1

echo ""
echo "Running Ficino..."
echo "Ctrl+C to quit"
echo ""

./build/Build/Products/Debug/Ficino.app/Contents/MacOS/Ficino
