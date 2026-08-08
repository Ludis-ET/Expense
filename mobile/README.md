# Santim mobile

Flutter client for Santim, with automatic bank-SMS capture on Android.

The Flutter layer is the UI. The capture pipeline is native Kotlin, because an
SMS broadcast receiver has to run in a cold process with no Dart VM attached —
the app being closed, swiped away, or the phone locked must not stop it.

## How capture works

```
bank SMS arrives
   │
   ▼
SmsReceiver.kt          manifest-registered, fires with the app closed
   │                    filters against the on-device sender allowlist
   │                    ~10s budget, so it only appends — never network
   ▼
IngestStore.kt          SQLite outbox; survives reboot and force-stop
   │
   ▼
UploadWorker.kt         WorkManager, exponential backoff
   │                    deletes rows only after the server acknowledges
   ▼
POST /api/v1/ingest/sms          auth: X-Device-Token
   │
   ▼
parser registry         amount, direction, balance, reference, payee
   │                    scores 0–100 confidence
   ▼
inbox_messages          PENDING → you review → real Transaction
```

Three properties are worth knowing because everything else depends on them:

- **`SMS_RECEIVED` is exempt** from the Android 8+ implicit-broadcast
  restrictions. That is what makes real-time capture possible with no
  foreground service and no persistent notification.
- **The upload is idempotent.** The server fingerprints every message
  (`user + sender + body + arrival minute`), so re-sending a batch whose
  response was lost is a no-op. The worker relies on this to retry freely.
- **The allowlist is enforced on the device.** A message from a sender you have
  not approved is dropped inside `onReceive` — it never reaches storage, let
  alone the network.

## Play Store

This app cannot be distributed on Google Play. `RECEIVE_SMS` / `READ_SMS` are
restricted by Google's SMS/Call Log policy, and expense tracking is not one of
the approved use cases. It is built for direct install.

If you ever need Play distribution, swap `SmsReceiver` for a
`NotificationListenerService` — every layer downstream of it stays identical.

## Running it

### 1. Backend

```bash
pnpm --filter @santim/backend db:migrate   # applies the sms_ingest migration
pnpm dev:backend                            # listens on :4000
```

For a real phone, the backend must bind to your LAN, not just loopback, and
your firewall has to allow the port.

### 2. Point the app at your server

**Release / production default** is the Render API:

`https://expense-7py7.onrender.com/api/v1`

That value is baked into release builds. Override only when developing against a
local backend:

```bash
flutter run --dart-define=SANTIM_API_URL=http://10.0.2.2:4000/api/v1
```

You can also change it in the app: **Settings → Server → Change server address**,
or the "Change" link on the sign-in screen. Include the `/api/v1` suffix.

### 3. Install / release APK

```bash
cd mobile
flutter build apk --release --dart-define=SANTIM_API_URL=https://expense-7py7.onrender.com/api/v1
```

Output:

`build/app/outputs/flutter-apk/app-release.apk`

Install:

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

The release build is signed with the debug key (see `android/app/build.gradle.kts`).
Fine for your own phone; replace it with a real signing config before giving the
APK to anyone else.

### 4. Set up capture

In the app: **Inbox → Set up capture**, then work down the five steps.

1. **Allow SMS** — the runtime permission.
2. **Pair this phone** — mints a device token, stored in
   EncryptedSharedPreferences. The plaintext is returned by the server exactly
   once and never held in Dart.
3. **Choose your banks** — lists the senders actually present in your SMS
   inbox, with a sample message and a guessed bank name. Sender IDs vary by
   carrier, so this is recognition rather than guesswork.
4. **Import past messages** — optional 90-day backfill.
5. **Keep it running** — the battery-optimisation exemption. Skip this on
   Xiaomi / Oppo / Vivo / Samsung and capture will work for a few days and then
   quietly stop.

## Tuning the parsers

The bank patterns in `backend/src/modules/ingest/parsers/` are best-effort
starting points, not transcriptions of real templates. Two tools close the gap:

- **Test how Santim reads it** — on any sender in the picker, runs a real
  message from your phone through the live parsers and shows every field it
  extracted plus the confidence score.
- **`POST /api/v1/ingest/preview`** — the same thing over HTTP, for iterating
  on a regex without touching the phone.

When you improve a pattern, hit **refresh** in the inbox. That calls
`/ingest/inbox/reparse`, which replays the new parsers over stored raw message
bodies — no re-uploading from the device.

## Messages that are not spending

Two shapes get read wrong by anything that treats every debit as an expense,
so the parser classifies them separately (`InboxMessage.movement`):

**ATM withdrawals.** Cash out of a machine has not left your net worth — it moved
from a bank wallet to your pocket. Booking it as spending double-counts it the
moment you actually spend the cash. Santim offers it as a **transfer into your
cash wallet** instead.

Which wallet is "cash" cannot be guessed — wallets are user-named and an account
typed `CASH` might be a mobile-money float — so the app asks once, in setup step
4 or under **Settings → Cash wallet**, and stores it as `User.cashAccountId`.

**Transfers between your own accounts.** When a message says money went to
another account, the parser pulls out the (usually masked) account number and
the server compares the last four digits against `Account.accountNumber` on your
wallets. A match becomes a **transfer**; no match stays an expense, because it
probably really did go to someone else.

Attach account numbers per wallet in **Messaging points** — paste the masked form
straight out of an SMS, only the trailing digits are compared.

Neither case can ever auto-post: both need a destination wallet the parser has no
way to know, so they are held below the confidence floor and always reach review.

## Reviewing: the swipe deck

**Inbox → Review all** opens a full-screen deck, one message per card.

- **Swipe right** (or the Record button) files it
- **Swipe left** (or Skip) dismisses it
- Verdict stamps fade in as you drag, so the gesture's meaning is clear before
  you commit
- The next card peeks out underneath, so it reads as a stack

Anything the parser could not work out is a highlighted chip on the card itself —
tap it, pick from a sheet, carry on. A missing field blocks the swipe and says
what it needs rather than half-committing. **Always use these for &lt;sender&gt;**
teaches the mapping so the next one arrives already filled.

The list view is still there for picking out one specific message.

## Importing history

Live capture starts the moment you finish setup — that boundary is stored as
`installedAt` and never moves, so re-pairing does not silently re-import.

Anything older needs **Import past messages**, which takes any date range:
presets from 30 days to everything, or a custom range. It shows how many
messages the range holds before you commit to it.

Re-importing an overlapping range is harmless. The on-device outbox de-duplicates
on `(sender, body, timestamp)` and the server fingerprints every message, so the
same text cannot land twice.

## Review vs auto-post

Everything waits for review by default. That is deliberate: a mis-parsed
transaction that auto-posted has to be unpicked from budget reservations and
balances, which is much worse than a tap.

Per sender you can turn on **Record without asking**. It requires all three of:

- an account mapped to that sender,
- a default category,
- a parse scoring ≥ 80 (amount + direction + at least one corroborating field,
  from a recognised sender).

Even then the write goes through the normal transaction endpoint, so the
overdraw guard applies. If it refuses, the message stays in the inbox with the
refusal shown as the reason.

## Offline & sync

The Flutter layer keeps working without signal. That is separate from SMS
capture (which already queues on-device in Kotlin) — this covers the rest of
the app.

```
cold start
   │
   ▼
sqflite cache          last accounts / categories / budgets /
                       dashboard / transactions / inbox / profile
   │
   ▼
UI paints immediately  (even in a tunnel)
   │
   ▼
network refresh        when reachable; otherwise stay on cache

writes (add / delete / inbox confirm / sender rules / …)
   │
   ▼
outbox                 ordered queue in sqflite
   │
   ▼
SyncEngine             drains on reconnect, with backoff
```

What you get on the phone:

- **Cold start offline** — cached balances and lists, not an empty shell
- **Optimistic ledger** — a transaction you add appears at once, tagged as
  pending until the server accepts it
- **Inbox review offline** — confirm / dismiss queue and sync later
- **Status pill + banner** — online / syncing / N pending / offline
- **Settings → Offline & sync** — sync now, see rejections, discard the queue
- **Sign-out wipes the cache** — the next account never inherits the last one's
  numbers

Network failures and server rejections are deliberately different: a dead
connection parks the write; a 4xx (overdraw, validation) drops it and tells
you why.

## Splash

Native `LaunchTheme` shows a solid Santim-tinted ground while the process
starts. Flutter then plays an animated brand splash while auth tokens and the
local cache hydrate, then hands off to login or the home shell.

## Project layout

```
lib/
  core/         api client (JWT + auto-refresh + NetworkException), theme
  offline/      LocalDb (cache + outbox), SyncEngine (connectivity + drain)
  models/       API shapes — amounts stay decimal strings until display
  state/        AuthStore, DataStore, CaptureStore (provider)
  widgets/      shared chrome + sync status
  screens/      dashboard, activity, inbox, plans, wallets, settings, splash
                capture/  setup wizard, sender picker, review sheet

android/app/src/main/kotlin/com/santim/mobile/
  MainActivity.kt        MethodChannel: configure, status, backfill, sync
  ingest/
    SmsReceiver.kt       real-time capture + multipart reassembly
    IngestStore.kt       SQLite outbox
    UploadWorker.kt      WorkManager delivery with backoff
    SmsHistoryReader.kt  sender discovery + history backfill
    IngestPrefs.kt       encrypted token/config store
    BootReceiver.kt      re-arms the worker after reboot
```

## Notes on two deliberate choices

**Raw SQLite instead of Room.** The outbox is one append-and-drain table. Room
would add a KSP annotation-processing toolchain to the build for no behaviour we
would actually use, and one more version pairing to keep in sync with Kotlin.

**`HttpURLConnection` instead of OkHttp.** One POST endpoint, called from a
worker. Not worth a dependency.
