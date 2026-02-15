#!/bin/bash
set -e

cd "$(dirname "$0")"

echo "🔨 Building music-context-cli..."
swift build -c release

echo "✍️  Signing with MusicKit entitlements..."
codesign --force \
  --sign B6646670039293BA4186A1C156B8271791D5A078 \
  --entitlements MusicContextCLI.entitlements \
  .build/release/music-context-cli

echo "✅ Verifying signature..."
codesign -dv --entitlements - .build/release/music-context-cli

echo ""
echo "✨ Done! Run with:"
echo "   .build/release/music-context-cli --musickit <catalog-id>"
