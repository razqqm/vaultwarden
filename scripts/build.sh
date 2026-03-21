#!/bin/bash
set -e

# Usage:
#   ./scripts/build.sh ios       # Build iOS (archive-ready)
#   ./scripts/build.sh android   # Build Android AAB (signed with YubiKey)
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
  echo "=== Building Android AAB (unsigned) ==="
  export YUBIKEY_SIGN=1
  flutter build appbundle --release

  UNSIGNED_AAB="build/app/outputs/bundle/release/app-release.aab"
  if [ ! -f "$UNSIGNED_AAB" ]; then
    echo "ERROR: AAB not found at $UNSIGNED_AAB"
    exit 1
  fi

  echo ""
  echo "=== Signing AAB with YubiKey ==="

  PKCS11_CFG="$(cd android && pwd)/yubikey-pkcs11.cfg"
  MAX_PIN_ATTEMPTS=3

  for ATTEMPT in $(seq 1 $MAX_PIN_ATTEMPTS); do
    read -s -p "YubiKey PIN: " YUBIKEY_PIN
    echo

    if [ -z "$YUBIKEY_PIN" ]; then
      echo "ERROR: PIN cannot be empty"
      continue
    fi

    # Use -storepass:env to avoid PIN leaking via ps/proc command line
    export YUBIKEY_PIN
    SIGN_EXIT=0
    SIGN_OUTPUT=$(jarsigner \
      -keystore NONE \
      -storetype PKCS11 \
      -storepass:env YUBIKEY_PIN \
      -addprovider SunPKCS11 \
      -providerArg "$PKCS11_CFG" \
      -sigalg SHA256withRSA \
      -digestalg SHA-256 \
      -J--add-exports=jdk.crypto.cryptoki/sun.security.pkcs11=ALL-UNNAMED \
      "$UNSIGNED_AAB" \
      "X.509 Certificate for Digital Signature" 2>&1) || SIGN_EXIT=$?

    # Clean up PIN from environment immediately
    unset YUBIKEY_PIN

    if [ $SIGN_EXIT -eq 0 ]; then
      break
    fi

    if echo "$SIGN_OUTPUT" | grep -qi "load failed\|pin incorrect\|pin invalid\|CKR_PIN_INCORRECT"; then
      REMAINING=$((MAX_PIN_ATTEMPTS - ATTEMPT))
      if [ $REMAINING -gt 0 ]; then
        echo "ERROR: Wrong PIN ($REMAINING attempts left)"
      else
        echo "ERROR: Wrong PIN. No attempts left."
        echo "WARNING: Further incorrect attempts may lock your YubiKey!"
        exit 1
      fi
    else
      echo "ERROR: jarsigner failed: $SIGN_OUTPUT"
      exit $SIGN_EXIT
    fi
  done

  echo ""
  if jarsigner -verify "$UNSIGNED_AAB" > /dev/null 2>&1; then
    echo "✓ Signature verified"
  else
    echo "ERROR: Signature verification FAILED"
    exit 1
  fi

  mkdir -p "$DESKTOP_FOLDER"
  cp "$UNSIGNED_AAB" "$DESKTOP_FOLDER/VaultApprover-${VERSION_NAME}+${NEW_BUILD}.aab"
  echo "✓ Signed AAB copied to: $DESKTOP_FOLDER/"
fi

echo ""
echo "Done: ${VERSION_NAME} (${NEW_BUILD})"
if [ -d "$DESKTOP_FOLDER" ]; then
  echo "Output: $DESKTOP_FOLDER/"
fi
