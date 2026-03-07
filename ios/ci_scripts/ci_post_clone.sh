#!/bin/sh
set -e

echo "=== ci_post_clone.sh ==="

# Install Flutter (latest stable)
echo "Installing Flutter (latest stable)..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1 "$HOME/flutter"
export PATH="$HOME/flutter/bin:$PATH"

flutter --version
flutter precache --ios

# Flutter build
echo "Running flutter pub get..."
cd "$CI_PRIMARY_REPOSITORY_PATH"
flutter pub get

echo "Running flutter build ios..."
flutter build ios --release --no-codesign

# CocoaPods
echo "Installing CocoaPods dependencies..."
cd "$CI_PRIMARY_REPOSITORY_PATH/ios"
pod install

echo "=== ci_post_clone.sh complete ==="
