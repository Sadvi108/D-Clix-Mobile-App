# D-CLIX — Club Management Mobile App

**Flutter** app for martial-arts academies. Members sign in to check in to class by QR, see
their timetable, book sessions, pay fees, and message the club; instructors get collections
and reports instead.

The app is a **client only**. All data comes from the third-party **Club.Api** backend
(`apimac.zyncbook.com`), which this repository does not own or deploy.

> **This repository is public.** Do not commit credentials, tokens or member data. The docs
> record live API contracts and observed backend behaviour — no account details.

## Stack

| | |
|---|---|
| App | Flutter 3.44.8, Dart 3.12, go_router, provider |
| Backend | Club.Api (ASP.NET, third-party) — REST + bearer JWT |
| Auth | Token in the OS secure store (Keychain / Keystore), never in SharedPreferences |
| Android | `com.dclix.clubapp` |
| iOS | `com.raigtech.dclix` (built and signed by `build-flutter-ipa.yml`) |
| Payments | Boost gateway via the backend's `/Bcpg` routes |

## Getting started

```bash
cd flutter_app
flutter pub get
```

### Run

```bash
flutter run                 # attached device or emulator
flutter run -d chrome       # web preview
```

Note on the web preview: the backend is plain HTTP and sends no CORS headers, so
**authenticated screens stay empty in a browser**. Sign-in and anything behind it need a
real device or emulator. The user guide (`#/user-guide`) works without an account.

### Test and analyze

```bash
flutter test                # offline service, navigation and widget tests
flutter analyze
```

Two suites are opt-in because they reach outside the process:

```bash
# Live API smoke test — probes every screen's endpoints and prints a wiring table.
flutter test test/live_api_smoke_test.dart \
  --dart-define=LIVE_USER=<id> --dart-define=LIVE_PASS=<password>

# Regenerate the user-guide screenshots (writes to assets/guide/).
flutter test tool/capture_guide_shots.dart --dart-define=CAPTURE=true
```

### Build a release APK

```bash
flutter build apk --release
```

Requires JDK 17 and an Android SDK. The current release configuration signs with the
local debug key, so this command produces an optimized test APK. Configure the original
release signing key before distributing an update. Pushing a `flutter-v*` tag builds and
publishes the APK through GitHub Actions.

## Layout

```
flutter_app/
  lib/
    screens/        one file per screen, plus payment/ and instructor_reports/
    services/       API client, session, payments, notifications, storage
    widgets/        shared UI
    theme/          palette, tokens, ThemeProvider
    router/         go_router configuration
    data/           static config and user-guide content
  test/             unit, wiring and render tests
  tool/             screenshot capture and its fake API (not part of `flutter test`)
  assets/guide/     user-guide screenshots, generated from fictional data
docs/               architecture, design and API contract notes
```

## How the app is verified

Beyond ordinary unit tests, a few suites guard classes of bug that type-checking cannot:

| Suite | What it catches |
|---|---|
| `api_wiring_test` | An endpoint path or HTTP verb that does not exist on the server. Checked against the real route table in `test/fixtures/club_api_routes.json` (73 paths). |
| `screen_wiring_test` | A screen with no data source, or one that quietly stopped calling its endpoint. |
| `navigation_targets_test` | A menu tile pointing at an unregistered route. |
| `material_ancestor_test` | A standalone route with no `Material` ancestor (an `InkWell` there crashes the screen). |
| `loading_state_test` | A screen that can never leave its loading state. |
| `guide_content_test` | Guide text that promises something the app does not do, and missing or orphaned screenshots. |

## Known constraints

These are backend limitations, recorded so they are not mistaken for bugs:

- **No push notifications.** Club.Api exposes no device-token route, so alerts are local:
  the app polls in the foreground and through a WorkManager job every ~15 minutes with the
  app closed.
- **Auto Pay is a reminder, not a mandate.** There is no recurring-payment route. The
  screen schedules a monthly reminder and pre-selects the months; the member still confirms.
- **`/Bcpg` is UAT-only.** The Boost routes 404 on production, so those calls — and only
  those — go to `apimacuat.zyncbook.com`, which is documented as serving a self-signed certificate without a host SAN.
  The Android trust file does not resolve Dart HTTP or hostname validation. Online payment
  needs a valid server certificate or production Boost routes; see the parity audit.
- **Cleartext HTTP is enabled** because the production API does not serve HTTPS.
- **New-student approval awaits the backend.** The Flutter list/detail/action flow follows
  the proposed RN contract and shows “Awaiting backend” when those routes are unavailable.

## Documentation

- [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) — API contracts and observed backend behaviour
- [`docs/DESIGN.md`](docs/DESIGN.md) — design system
- [`docs/react-native-parity-audit.md`](docs/react-native-parity-audit.md) — exact RN reference, corrected gaps, route mapping and verification limits

## History

This app was an Expo / React Native codebase through **v2.11.1**. The Flutter rewrite
replaced it at **2.12.0**. The Expo app is preserved in full at tag
[`v2.11.1`](https://github.com/Sadvi108/Club-Management-Mobile-app/tree/v2.11.1) —
`git checkout v2.11.1` restores it.

Both ship as `com.dclix.clubapp`, and the Flutter build's versionCode (18) is above the
Expo release's (17). Installing over an existing release also requires its original signing
key. The checked-in Android release configuration currently uses the debug key.

## Conventions

- Commit messages say what changed and why, not how.
- Comments explain the non-obvious — a workaround, a server quirk, a decision that looks
  wrong until you know the constraint.
- Nothing that is not verified is described as verified.

## Live updates and test APK

Flutter 2.12.1+19 adds foreground message and data refresh. See [live API verification](docs/realtime-verification.md) for tested behavior and remaining backend/device requirements, and [APK release notes](docs/releases/flutter-v2.12.1.md) for signing and installation limits. Instant closed-app push still requires backend/Firebase integration.
