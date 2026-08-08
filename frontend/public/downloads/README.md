# APK drop folder

Put the release build here as `santim.apk`:

```bash
cd mobile
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk ../frontend/public/downloads/santim.apk
```

The download button, the mobile banner, and the popup ad all point at
`/downloads/santim.apk` by default. To host the file somewhere else instead, set
`NEXT_PUBLIC_ANDROID_APP_URL` and leave this folder empty.

Before handing the APK to anyone other than yourself, replace the debug signing
config in `mobile/android/app/build.gradle.kts` with a real one — the release
build is currently signed with the debug key.
