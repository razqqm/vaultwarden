#!/bin/sh
set -e

echo "=== ci_post_clone.sh ==="

# Install Flutter (latest stable)
echo "Installing Flutter (latest stable)..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

flutter --version
flutter precache --ios

# Generate plugin registrant and get dependencies
echo "Running flutter pub get..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

# CocoaPods (must run BEFORE flutter build to fix bridging header scan)
echo "Installing CocoaPods dependencies..."
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
pod install

# Flutter build
echo "Running flutter build ios..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter build ios --release --no-codesign

echo "=== ci_post_clone.sh complete ==="
