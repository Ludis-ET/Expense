# Release signing

Santim is distributed as a direct APK download, not through the Play Store. That
makes the signing key load-bearing in a way it would not be otherwise: Android
lets an APK replace an installed app **only when both are signed with the same
key**. That check is the only thing standing between a user and a trojaned build
that installs over the real Santim and inherits its data directory — including
session tokens and SMS access.

Until now, release builds were signed with the Android **debug** keystore. Its
password is `android`, its alias is `androiddebugkey`, and a copy sits in
`~/.android/debug.keystore` on every machine with an Android SDK installed. So
the check passed for anyone who wanted it to.

## Generate the keystore, once

```bash
keytool -genkeypair -v \
  -keystore ~/santim-release.jks \
  -keyalg RSA -keysize 4096 -validity 10000 \
  -alias santim
```

Choose a strong password. You will be asked for it twice.

## Point the build at it

Create `mobile/android/key.properties` — this file is gitignored and must stay
that way:

```properties
storeFile=/absolute/path/to/santim-release.jks
storePassword=<the password you chose>
keyAlias=santim
keyPassword=<usually the same password>
```

Then `flutter build apk --release` picks it up automatically. Without the file
the release build still completes but is left **unsigned** and logs a warning —
deliberately, so a misconfigured machine cannot silently produce a debug-signed
artifact again.

## Back the keystore up

Losing it means you can never ship an update to anyone who installed the app:
their device will refuse the new signature. Keep an offline copy somewhere you
would keep a password manager export. Do not commit it.

## The one-time cost of fixing this

Existing installs are debug-signed. They cannot be updated in place to a
properly signed build — the signatures differ, which is precisely the protection
working as intended. Everyone currently running Santim needs to uninstall and
reinstall once. After that, updates work normally forever.

Worth doing before the user base grows, not after.
