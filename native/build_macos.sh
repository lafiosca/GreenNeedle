#!/usr/bin/env bash
# Build greenneedle.c as a universal macOS dylib (arm64 + x86_64).
# Requires Xcode Command Line Tools: xcode-select --install
#
# Usage:
#   cd native && ./build_macos.sh
#
# Output: greenneedle.dylib (placed in the GreenNeedle mod directory)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/greenneedle.c"
OUT_DIR="$SCRIPT_DIR/.."   # mod root
OUT="$OUT_DIR/greenneedle.dylib"

CFLAGS="-O2 -fPIC -Wall -Wextra -std=c11 -lm"

echo "Building arm64..."
clang $CFLAGS -arch arm64  -dynamiclib -o "$SCRIPT_DIR/greenneedle_arm64.dylib"  "$SRC"

echo "Building x86_64..."
clang $CFLAGS -arch x86_64 -dynamiclib -o "$SCRIPT_DIR/greenneedle_x86_64.dylib" "$SRC"

echo "Creating universal binary..."
lipo -create \
    "$SCRIPT_DIR/greenneedle_arm64.dylib" \
    "$SCRIPT_DIR/greenneedle_x86_64.dylib" \
    -output "$OUT"

# Clean up arch-specific intermediates
rm "$SCRIPT_DIR/greenneedle_arm64.dylib" "$SCRIPT_DIR/greenneedle_x86_64.dylib"

echo "Done: $OUT"
file "$OUT"
