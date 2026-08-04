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
BUILD_NUMBER=$(awk '/^version:/{print $2}' pubspec.yaml | cut -d'+' -f2)

# A release APK is what actually gets installed/updated on a device, so its
# versionCode (this build number) needs to keep increasing - otherwise
# Android's package installer can't reliably tell a new install from an
# in-place update of the same app, and special access grants like full-
# screen-intent permission (see NotificationService.initialize) get reset
# instead of carried over. Debug builds are only ever run via `flutter run`
# during iteration, never distributed, so they don't need this.
if [ "$BUILD_TYPE" = "release" ]; then
    NEW_BUILD_NUMBER=$((BUILD_NUMBER + 1))
    sed -i "s/^version: ${APP_VERSION}+${BUILD_NUMBER}$/version: ${APP_VERSION}+${NEW_BUILD_NUMBER}/" pubspec.yaml
    BUILD_NUMBER="$NEW_BUILD_NUMBER"
fi

echo "Building ${BUILD_TYPE} APK (version ${APP_VERSION}+${BUILD_NUMBER})..."
flutter build apk "--${BUILD_TYPE}"

APK_PATH="build/app/outputs/flutter-apk/app-${BUILD_TYPE}.apk"
echo "APK: ${PROJECT_DIR}/${APK_PATH} ($(du -h "$APK_PATH" | cut -f1))"
