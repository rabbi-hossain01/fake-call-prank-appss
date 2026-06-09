# Fake Call Recording / Prank - Flutter App

This app is for consent-based prank/skit/demo audio only. It records two speakers sequentially on one device, pitch-shifts only Person B chunks, merges chunks in order, applies a telephone-style filter, and exports an MP3.

## Included

- `lib/main.dart` complete Flutter UI and logic
- Android native Kotlin `MediaStore` export to `Downloads/PrankCallRecorder`
- FFmpeg commands for pitch shift, merge, and phone/radio effect
- Android permissions and Gradle config

## Build APK

You need Flutter SDK installed locally.

```bash
flutter pub get
flutter build apk --release
```

APK location after build:

```text
build/app/outputs/flutter-apk/app-release.apk
```

For testing:

```bash
flutter run
```

## Notes

- Android 10+ exports using MediaStore into Downloads/PrankCallRecorder.
- Android below 10 uses public Downloads folder and may require storage permission.
- The app records microphone audio only. It does not record real phone calls.
