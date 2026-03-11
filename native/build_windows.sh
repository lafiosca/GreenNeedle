#!/usr/bin/env bash
# Cross-compile greenneedle.c as a Windows x86_64 DLL.
# Requires mingw-w64: brew install mingw-w64
#
# Usage:
#   cd native && ./build_windows.sh
#
# Output: greenneedle.dll (placed in the GreenNeedle mod directory)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$SCRIPT_DIR/greenneedle.c"
OUT_DIR="$SCRIPT_DIR/.."   # mod root
OUT="$OUT_DIR/greenneedle.dll"

x86_64-w64-mingw32-gcc -O2 -Wall -Wextra -std=c11 -shared -o "$OUT" "$SRC" -lm

echo "Done: $OUT"
file "$OUT"
