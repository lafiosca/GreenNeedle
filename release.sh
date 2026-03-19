#!/usr/bin/env bash
set -euo pipefail

# Build a release zip for GreenNeedle.
# Usage: ./release.sh
# Reads version from lovely.toml and creates GreenNeedle-v{VERSION}.zip in /tmp.

cd "$(dirname "$0")"

VERSION=$(grep '^version' lovely.toml | sed 's/.*"\(.*\)"/\1/')
if [ -z "$VERSION" ]; then
    echo "Error: could not read version from lovely.toml" >&2
    exit 1
fi

OUTFILE="/tmp/GreenNeedle-v${VERSION}.zip"
STAGING="/tmp/GreenNeedle"
rm -f "$OUTFILE"
rm -rf "$STAGING"
mkdir "$STAGING"

cp \
    GreenNeedle.lua \
    GreenNeedle_main.lua \
    GreenNeedle_search.lua \
    GreenNeedle_UI.lua \
    GreenNeedle_keyhandler.lua \
    nativefs.lua \
    lovely.toml \
    greenneedle.dylib \
    greenneedle.dll \
    "$STAGING/"

(cd /tmp && zip -r "$OUTFILE" GreenNeedle/)
rm -rf "$STAGING"

echo "Created $OUTFILE"
