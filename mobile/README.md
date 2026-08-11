# Santim Android app

A Flutter client that mirrors the responsive web app screen for screen. It talks
to the same Express API (`backend/`) over REST, so an account created on the web
signs straight in here.

## Running it

```bash
flutter pub get
flutter run
```

### Browser (Chrome) + local backend

Use this to preview the app in Chrome and hit your local API.

**Terminal 1 backend** (from repo root):

```bash
cd backend
# Ensure backend/.env has DATABASE_URL, JWT_SECRET, and CORS including the web port:
# CORS_ORIGINS=http://localhost:5173,http://127.0.0.1:5173
pnpm install   # or npm install
pnpm dev       # API at http://localhost:4000
```

**Terminal 2 Flutter web**:

```bash
cd mobile
flutter pub get
flutter run -d chrome --web-port=5173 --dart-define=API_BASE=http://localhost:4000/api/v1
```

Open **http://localhost:5173**, sign in or register, and the app talks to `http://localhost:4000/api/v1`.

Without `--dart-define`, the app uses the Render API (`https://expense-7py7.onrender.com/api/v1`).

**CORS:** the browser blocks cross-origin calls unless your backend `.env` lists the Flutter web origin. Match the port you use in `flutter run --web-port=…` (5173 above).

**Database:** first time locally, run migrations in `backend/`:

```bash
pnpm db:migrate
pnpm db:seed    # optional demo data
```

The app ships pointed at production by default. Override at build time:

```bash
flutter run --dart-define=API_BASE=http://10.0.2.2:4000/api/v1   # host machine from the Android emulator
```

## Building

```bash
flutter build apk --release                    # one universal APK (~52 MB)
flutter build apk --release --split-per-abi     # per-ABI, ~16-20 MB each
```

Artifacts land in `build/app/outputs/flutter-apk/`. The release build is signed
with the debug key swap in a real `signingConfig` in
[android/app/build.gradle.kts](android/app/build.gradle.kts) before distributing.

The app is not on Google Play (Play restricts the permissions an expense tracker
needs), so the site serves the APK directly.

## How it maps to the web app

| Web route                   | Android                                    |
| --------------------------- | ------------------------------------------ |
| `/dashboard`                | Home tab                                   |
| `/transactions`             | Activity tab, plus the raised **+** button |
| `/accounts`                 | Wallets tab                                |
| `/budgets`, `/budgets/[id]` | Plan tab → plan detail                     |
| `/analytics`                | Drawer → Analytics (4 sections)            |
| `/tab`                      | Drawer → Money Tab                         |
| `/guides`                   | Drawer → Guides                            |
| `/assistant`                | "Ask Santim" bar above the bottom nav      |
| `/settings`                 | Drawer → Settings, with four sub-screens   |
| wishlist panel              | Plan tab → Wishlist                        |
| recurring panel             | Activity tab → repeat icon                 |

## Bank SMS capture (Android APK)

Santim can read bank SMS on Android, parse them on the server, and let you
swipe to confirm drafts. Google Play does not allow this permission for expense
apps, so distribute with a direct install:

```bash
cd mobile
flutter build apk --release
# Install: adb install build/app/outputs/flutter-apk/app-release.apk
```

In the app: topbar **inbox** icon → setup wizard (SMS permission, pair phone,
cash wallet, battery exemption, messaging points). Settings → **Bank SMS** for
capture toggle, import history, and paste preview.

## Layout

```
lib/
  core/
    api/          ApiClient   REST + one transparent token refresh on a 401
    theme/        tokens.dart is globals.css; theme.dart is radii + motion curves
    utils/        money/date formatting, Ethiopic calendar, the finance icon set
  models/         Dart mirrors of frontend/src/lib/types.ts
  state/          AuthState, DataState (shared cache), PrefsState (device-local)
  widgets/        glass.dart, motion.dart, ui.dart, fields.dart, charts.dart
  features/       one folder per screen
```

### Design system

`core/theme/tokens.dart` carries the same hex values as the web app's
`globals.css`, in both light and dark, so the two clients cannot drift. The
motion in `widgets/motion.dart` is a port of the CSS keyframes `fade-in-up`,
`shimmer`, `bounce-dot`, `sync-pop`, `lock-shake` on the same durations and
the same `cubic-bezier(0.22, 1, 0.36, 1)` curve.

Glassmorphism lives in `widgets/glass.dart`: `GlassCard` is the web's
`@utility glass` (80% surface over a 12px backdrop blur) with a specular top
edge, and `MeshBackground` is `.bg-mesh` + `.bg-grid` with the two orbs drifting
on the same 7s and 8s loops as the splash.

Charts are hand-painted with `CustomPainter` rather than pulled from a package,
matching the web app's own inline SVG charts.

### A note on the analyzer

`flutter analyze` is clean. The one deliberate deviation from the web codebase is
that the `Category` model is called `TxCategory` here Flutter's `foundation`
library already exports a `Category` annotation, and the collision would
otherwise need a `hide` on every import.
