#!/bin/bash
#
# Copy a built jotes APK to a synced folder
#
# Usage: ./copy-to-sync.sh [-t debug|release]
#   -t: build type, debug or release (default: release)
#
# The APK must already be built (run ./build-apk.sh first).
# The APK will be copied to ~/Sync/ with a timestamped filename.

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

BUILD_TYPE="release"

while getopts "t:" opt; do
    case "$opt" in
        t) BUILD_TYPE="$OPTARG" ;;
        *) echo "Usage: $0 [-t debug|release]"; exit 1 ;;
    esac
done

APK_PATH="build/app/outputs/flutter-apk/app-${BUILD_TYPE}.apk"

if [[ ! -f "$APK_PATH" ]]; then
    echo "Error: APK not found: $APK_PATH"
    echo "Run ./build-apk.sh [-t ${BUILD_TYPE}] first."
    exit 1
fi

SYNC_DIR="$HOME/Sync"

if [[ ! -d "$SYNC_DIR" ]]; then
    echo "Error: Synced directory not found: $SYNC_DIR"
    exit 1
fi

APP_VERSION=$(awk '/^version:/{print $2}' pubspec.yaml | cut -d'+' -f1)
TIMESTAMP=$(date -u +%Y%m%d-%H%M%S -r "$APK_PATH")
DEST_FILENAME="jotes-${BUILD_TYPE}-${APP_VERSION}-${TIMESTAMP}.apk"
DEST_PATH="${SYNC_DIR}/${DEST_FILENAME}"

cp "$APK_PATH" "$DEST_PATH"

echo "Copied APK to synced directory:"
echo "  Source: $APK_PATH"
echo "  Dest:   $DEST_PATH"
echo "  Size:   $(du -h "$DEST_PATH" | cut -f1)"
