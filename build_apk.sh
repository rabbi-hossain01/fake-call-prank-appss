#!/usr/bin/env bash
set -e

# Run this from the project root on a computer with Flutter installed.
# If Android Gradle wrapper files are missing, Flutter can regenerate them.
if [ ! -f "android/gradlew" ]; then
  echo "Android Gradle wrapper not found. Generating/updating Android platform files..."
  flutter create --platforms=android .
fi

flutter pub get
flutter build apk --release

echo "APK created at: build/app/outputs/flutter-apk/app-release.apk"
