#!/bin/bash
set -e

cd "$(dirname "$0")"

pkill -9 AlmostHumanAfterAll 2>/dev/null || true
sleep 0.5

xcodebuild -project AlmostHumanAfterAll.xcodeproj \
  -scheme AlmostHumanAfterAll \
  -derivedDataPath ./build \
  build 2>&1 | tail -1

echo ""
echo "Running AlmostHumanAfterAll..."
echo "Ctrl+C to quit"
echo ""

./build/Build/Products/Debug/AlmostHumanAfterAll.app/Contents/MacOS/AlmostHumanAfterAll
