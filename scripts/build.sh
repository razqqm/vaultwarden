#!/bin/bash
set -e

# Usage:
#   ./scripts/build.sh ios       # Build iOS (archive-ready)
#   ./scripts/build.sh android   # Build Android AAB
#   ./scripts/build.sh both      # Build both

PUBSPEC="pubspec.yaml"

# Read current version
CURRENT=$(grep '^version:' "$PUBSPEC" | head -1)
VERSION_NAME=$(echo "$CURRENT" | sed 's/version: *//;s/+.*//')
BUILD_NUMBER=$(echo "$CURRENT" | sed 's/.*+//')

# Increment build number
NEW_BUILD=$((BUILD_NUMBER + 1))
NEW_VERSION="version: ${VERSION_NAME}+${NEW_BUILD}"

echo "Version: ${VERSION_NAME}  Build: ${BUILD_NUMBER} → ${NEW_BUILD}"

# Update pubspec.yaml
sed -i '' "s/^version: .*/$NEW_VERSION/" "$PUBSPEC"

PLATFORM="${1:-both}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
DESKTOP_FOLDER="$HOME/Desktop/VaultApprover-${VERSION_NAME}-${NEW_BUILD}-${TIMESTAMP}"

if [ "$PLATFORM" = "ios" ] || [ "$PLATFORM" = "both" ]; then
  echo ""
  echo "=== Building iOS ==="
  flutter build ios --release --no-codesign
  echo "✓ iOS build complete (${VERSION_NAME}+${NEW_BUILD})"
fi

if [ "$PLATFORM" = "android" ] || [ "$PLATFORM" = "both" ]; then
  echo ""
  echo "=== Building Android AAB ==="
  read -s -p "YubiKey PIN: " YUBIKEY_PIN
  echo
  export YUBIKEY_SIGN=1
  export YUBIKEY_PIN
  flutter build appbundle --release
  unset YUBIKEY_PIN

  AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
  if [ -f "$AAB_PATH" ]; then
    mkdir -p "$DESKTOP_FOLDER"
    cp "$AAB_PATH" "$DESKTOP_FOLDER/VaultApprover-${VERSION_NAME}+${NEW_BUILD}.aab"
    echo "✓ AAB copied to Desktop: $DESKTOP_FOLDER/"
  fi
fi

echo ""
echo "Done: ${VERSION_NAME} (${NEW_BUILD})"
if [ -d "$DESKTOP_FOLDER" ]; then
  echo "Output: $DESKTOP_FOLDER/"
fi
