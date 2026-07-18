#!/bin/bash
#
# Build jotes APK
#
# Usage: ./build-apk.sh [-t debug|release]
#   -t: build type, debug or release (default: release)

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

APP_VERSION=$(awk '/^version:/{print $2}' pubspec.yaml | cut -d'+' -f1)

echo "Building ${BUILD_TYPE} APK (version ${APP_VERSION})..."
flutter build apk "--${BUILD_TYPE}"

APK_PATH="build/app/outputs/flutter-apk/app-${BUILD_TYPE}.apk"
echo "APK: ${PROJECT_DIR}/${APK_PATH} ($(du -h "$APK_PATH" | cut -f1))"
