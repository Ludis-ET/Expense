# Android in-app updates (OTA)

Sideloaded Santim builds can update themselves without ADB. The backend advertises the latest APK; the app pops a sheet, downloads it, and opens the system installer.

## One-time setup

1. **Ship a build that includes the updater** (this feature). Users on older APKs still need one manual install.
2. On the API host (Render / cPanel), set env vars:

| Variable | Example | Notes |
|----------|---------|--------|
| `ANDROID_LATEST_VERSION_CODE` | `4009` | Must match `pubspec.yaml` build number (`1.0.10+4009` → `4009`) |
| `ANDROID_LATEST_VERSION_NAME` | `1.0.10` | Shown in the popup |
| `ANDROID_APK_URL` | `https://…/app-release.apk` | Direct HTTPS link to the APK |
| `ANDROID_CHANGELOG` | `Outlook + chat history` | Optional “What’s new” text |
| `ANDROID_FORCE_UPDATE` | `false` | `true` blocks “Not now” |
| `ANDROID_MIN_VERSION_CODE` | `2000` | Optional floor — older builds are forced to update |

3. Host the APK somewhere public (GitHub Releases, Cloudflare R2, S3, your CDN). Do **not** put a huge APK on the free Render disk if you can avoid it.

4. Confirm: `GET https://your-api/api/v1/app/android-update` returns JSON with `configured: true` and your `versionCode`.

## Publish a new version

```bash
# 1. Bump mobile/pubspec.yaml — e.g. 1.0.10+4009 (must be > what's on the phone)
# 2. Build
cd mobile
flutter build apk --release --target-platform android-arm64 \
  --dart-define=API_BASE=https://expense-7py7.onrender.com/api/v1

# 3. Upload build/app/outputs/flutter-apk/app-release.apk to your host
# 4. Update ANDROID_* env on the API and restart the Node app
```

Next cold start (or **Settings → Check for updates**), phones on an older `versionCode` see the popup → **Download & install** → system confirm → done.

## Notes

- Requires “Install unknown apps” / install permission for Santim (Android prompts once).
- Optional updates can be dismissed; that version is skipped until a newer code ships (or force / min version).
- Play Store distribution would use Google Play In-App Updates instead of this OTA path.
