# পিসিতে Android Studio/Flutter না থাকলে APK বানানোর সহজ নিয়ম

এই প্রজেক্টে GitHub Actions workflow দেওয়া আছে। এতে আপনার পিসিতে Android Studio বা Flutter SDK লাগবে না। GitHub-এর cloud server APK build করবে।

## কী লাগবে
- একটি GitHub account
- Internet connection
- এই project ZIP extract করা

## ধাপ

1. GitHub.com এ যান এবং New repository তৈরি করুন।
2. Repository public বা private যেটাই দেন সমস্যা নেই।
3. ZIP extract করার পর `fake_call_prank_flutter` ফোল্ডারের ভিতরে যান।
4. ওই ফোল্ডারের ভিতরের সব file/folder repository root-এ upload করুন।
   - গুরুত্বপূর্ণ: `pubspec.yaml` যেন repository-এর প্রথম/root জায়গায় থাকে।
   - `.github/workflows/build-apk.yml` ফাইলটাও root-এর ভিতরে থাকতে হবে।
5. Upload/Commit করার পর GitHub-এর `Actions` tab খুলুন।
6. `Build Android APK` workflow খুলুন।
7. `Run workflow` চাপুন।
8. Build শেষ হলে একই workflow run page-এর নিচে `Artifacts` section পাবেন।
9. `fake-call-prank-debug-apk` download করুন। ভিতরে `app-debug.apk` থাকবে।

## APK কোথায় পাবেন?
GitHub Actions artifact-এর ভিতরে:

`app-debug.apk`

## Local build করতে চাইলে
পিসিতে Flutter install থাকলে:

```bash
flutter pub get
flutter build apk --debug
```

APK path:

`build/app/outputs/flutter-apk/app-debug.apk`
