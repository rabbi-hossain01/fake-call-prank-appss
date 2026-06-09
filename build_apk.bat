@echo off
REM Run this from the project root on Windows with Flutter installed.
IF NOT EXIST android\gradlew (
  echo Android Gradle wrapper not found. Generating/updating Android platform files...
  flutter create --platforms=android .
)

flutter pub get
flutter build apk --release

echo APK created at: build\app\outputs\flutter-apk\app-release.apk
pause
