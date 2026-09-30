# D-CLIX — file-by-file codebase description

What every file in this repository is, and why it exists. Written 2026-09-20 against the
working tree at commit `5d200fc` (plus uncommitted Auto Pay work — see the last section).

**The app in one line:** a Flutter client for martial-arts academies. Members check in by QR,
see their timetable, book classes, pay fees and message the club; instructors get collections
and reports instead. It owns no backend — everything comes from the third-party **Club.Api**
(`apimac.zyncbook.com`). It was an Expo/React Native app through v2.11.1 and was rewritten in
Flutter at 2.12.0, which is why so many files say "port of `frontend/app/<x>.tsx`".

Scale: 381 tracked files, ~33,900 lines of Dart across 149 files (lib ≈ 20k, test ≈ 4k,
tool ≈ 1k), 95 PNGs, 26 Markdown docs.

---

## 1. Repository root

| File | What it is |
|---|---|
| `README.md` | Entry point. Stack table, run/test/build commands, repo layout, the verification-suite table, and the **Known constraints** list (no push notifications, Auto Pay is not a mandate, `/Bcpg` is UAT-only, cleartext HTTP, new-student approval awaits the backend). Also states the repo is public — no credentials, no member data. |
| `docs/` | Architecture, design system, specs, release notes. Section 2. |
| `flutter_app/` | The entire app. Sections 3–10. |
| `design_guidelines.json` | Design tokens from the **original April-2026 "Apex Academy" prototype** — Poppins/Inter, indigo→purple gradient, Tailwind-flavoured class strings. The shipped app is orange/black and its real tokens live in `lib/theme/app_theme.dart`. Historical; do not treat as current. |
| `.github/workflows/build-flutter-apk.yml` | The only CI job. On PR/push to `main` and on `flutter-v*` tags: JDK 17 + Flutter 3.44.8 → `flutter pub get` → `flutter analyze --no-fatal-infos` → `flutter test` → writes `android/key.properties` from repository secrets (or warns and falls back to the debug key) → builds APK **and** app bundle → checks which key signed it → verifies the R46 certificate is actually inside the APK → publishes a GitHub release on a tag, marked **pre-release** when debug-signed. |
| `.gitignore` | Long and deliberately paranoid: `.env*`, `*token.json*`, `*credentials.json*`, `*.jks`, keystores, plus the usual Node/Next/Flutter build output. (A blanket `*.pem` rule here once hid `uat_apimacuat.pem` from a clean checkout — see `test/android_resources_test.dart`.) |
| `.gitattributes` | `* text=auto eol=lf`; PNG/JPG/TTF marked binary. |
| `.gitconfig` | Committed author identity (`emergent-agent-e1`) from the original agent-built scaffold. |
| `.vscode/launch.json` | Four Dart launch configs — debug / profile / release / Chrome — all pointing at `flutter_app/lib/main.dart` with `cwd` set to `flutter_app`. |

---

## 2. `docs/`

### Current reference

| File | Contents |
|---|---|
| `ARCHITECTURE.md` | **The most important doc in the repo.** The live API contract as actually probed, not as documented. Covers: prod vs UAT environments and why only `/Bcpg/*` crosses hosts; the multipart shape of `/Outstanding/PayInvoices` (and that `PaymentMethod: 3` settles an invoice with no payment — never send it); Boost's JSON body and that the `?t=` in the returned URL is a checkout token, *not* a `VerifyPayment` reference; the class-booking quirks (weekly timetable, `classLimit` is capacity not availability, `BookNow` accepts duplicates, `NextBookings` is always `[]`); attendance check-in (`attendanceType` must be 1, the centre QR is `TC-` + 8 digits, and the route can only ever check in the token holder — so an instructor register is impossible without a new backend route); the absence of any *dedicated* push-token route (server push is unverified, not impossible — the old app registered the device through `DeviceId` at login); the report-route quirks (`reportType` cast to int, `meta.code: 0` failure envelopes, an envelope that omits `data` entirely, `/Reports/GradingSchedule` ignoring all its filters, `/Reports/TournamentSummary` being a medal summary with no dates); and the receipt-PDF id trap (use the **invoiceId** in the third slot or you get a blank PDF). |
| `DESIGN.md` | The design system, still written in React Native terminology; the Flutter tokens live in `lib/theme/`. |
| `react-native-parity-audit.md` | The 2026-09-11 audit against Expo v2.11.1 (`5223e60`): what ported, what was corrected, route mapping, and the honest limits of the verification. |
| `realtime-verification.md` | What "live updates" actually means in 2.12.1+19 — 5 s messaging poll, 15 s data poll, ~15 min background job — and what still needs backend/Firebase work. |
| `android-signing.md` | Upload key, Play App Signing, the CI secrets, and the warning that losing the keystore blocks Play uploads until Google resets the upload key. |

### Specs (agreed contracts, some awaiting the backend)

| File | Contents |
|---|---|
| `specs/2026-09-15-manual-attendance.md` | Why an instructor cannot mark a register today, and the proposed `/Attendance/MarkByInstructor` contract the app already implements behind a route-table check. |
| `specs/2026-09-15-progress-belt-grading.md` | Progress Report / Belt / Grading spec, **agreed jointly with the Codex-built repo** so both implementations match. Source of the shared cases in `test/progress_stats_test.dart`. |
| `specs/2026-09-15-tournaments.md` | Why Upcoming/Past tournaments cannot exist (one route, medal tallies, no dates) and what the backend would need to add. |
| `superpowers/specs/2026-07-28-uat-boost-gateway-integration.md` | The Boost integration in full — 363 lines, §6 is the latest state. Repro for the two backend-owned UAT blockers. |
| `superpowers/specs/2026-07-29-class-booking-contract.md` | The live-probed booking contract behind `lib/services/class_booking.dart`. |
| `superpowers/specs/2026-07-11-new-student-approval.md` | The four proposed online-submission endpoints; the screens ship in an "Awaiting backend" state. |
| `superpowers/specs/2026-07-08-security-audit.md` | Six-question audit; client fixes marked ✅, backend-owned items ⚠️. |
| `superpowers/specs/2026-06-26-club-app-features-design.md` | Payments / Home / Settings feature design (RN era). |
| `superpowers/specs/2026-07-02-offers-notifications-chat-navbar-design.md` | Live offers, device alerts, academy chat, responsive nav bar. |
| `superpowers/specs/2026-09-17-boost-dues-monthly-gateway-design.md` | The newest design: routing Due Payment and Monthly Payment through Boost (Option A), pending confirmation of a backend bug. This is what commit `5d200fc` added. |
| `superpowers/plans/2026-06-26-payments-phase1.md` | 772-line task-by-task payments plan (Billplz era — superseded by Boost). |
| `superpowers/2026-07-29-tech-debt-audit.md` | Tech-debt audit of the retired `frontend/`. |

### History and releases

`2026-04-prototype-brief.md` is the original "Apex Academy" PRD, explicitly marked superseded.
`flutter-parity-plan.md` is a 12-line stub pointing at the audit.
`releases/flutter-v2.12.1.md` … `v2.13.3.md` are member-facing release notes; 2.13.3 is the
Android certificate fix for missing photos on Android 7–12.

`parity-captures/{dark,light}/*.png` — 38 screenshots used as the visual parity reference
against the Expo app.

`diagrams/` — **untracked.** A generated interactive runtime-architecture page
(`dclix-runtime-architecture.html`, 826 KB) plus its light/dark visual-check renders at two
sizes and the JSON that produced them.

---

## 3. `flutter_app/` — project configuration

| File | Notes |
|---|---|
| `pubspec.yaml` | Name `dclix_app`, version **2.13.2+23**, SDK ≥3.3. Dependency comments carry the reasoning: `workmanager ^0.10.3` (0.5.x used the dead v1 embedding), `flutter_secure_storage` for the bearer token, `flutter_local_notifications` with a bundled sound, `flutter_inappwebview` for Boost checkout, `nfc_manager`, `mobile_scanner`, `pdf`+`printing`, `cached_network_image`. **`crypto` is deliberately gone** — the merchant secret moved to the backend. Registers the Ionicons font and four asset folders, and configures `flutter_launcher_icons` from `assets/branding/app-icon.png`. A comment pins the versioning rule: the Flutter build's `versionCode` must stay above the Expo app's 17, because both ship as `com.dclix.clubapp`. |
| `pubspec.lock` | Resolved dependency graph. Committed. |
| `analysis_options.yaml` | Stock `flutter_lints` include; no custom rules enabled. |
| `.metadata` | Flutter tool bookkeeping (revision, stable channel, `project_type: app`). |
| `.gitignore` | Flutter-specific ignores on top of the root one. |
| `api_tests.http` | VS Code REST Client scratch file covering the API by hand. Credentials come from a gitignored `.env` via `{{$dotenv DCLIX_TEST_USER}}` — literal passwords were scrubbed and `test/no_committed_credentials_test.dart` now enforces it. |

---

## 4. `lib/` — application entry, config, router

### `lib/main.dart` (129)
`main()` installs the extra trust anchor **before any request** (`ExtraTrust.install()`), locks
portrait, and runs the app under a `MultiProvider` holding `ThemeProvider` and the
`UserSession` singleton. `DClixApp` wires three things worth knowing:
- **notification taps** — `NotificationService.onTap` stashes a payload and navigates once the
  session is loaded and logged in, so a cold launch from the tray lands on `/chat` (or
  `/autopay`) rather than nowhere;
- **lifecycle** — notification polling starts on resume, stops on anything else;
- **`MaterialApp.router`** with a custom `ScrollBehavior` (drag from mouse/trackpad/stylus too,
  so web and desktop don't feel broken) and an OS text-scale clamp of 0.85–1.30 applied once,
  globally, instead of per-screen.

### `lib/config/`
- **`app_version.dart`** (9) — `kAppVersion` / `kAppBuild`, single source of truth for the
  version shown in the UI. Checked against `pubspec.yaml` by a test, because the profile
  screen once hardcoded "v1.0.0" and drifted several releases behind.
- **`feature_flags.dart`** (4) — one flag, `kPrepayPayEnabled = true`, gating advance-month
  payment execution.

### `lib/router/app_router.dart` (368)
The whole navigation map, `go_router`. Two page transitions are defined locally: `_fadeThrough`
(320 ms fade + slight lift, used for pushes) and `_tabFade` (220 ms cross-fade, no slide,
because lateral motion reads wrong when the tab bar doesn't move). A global `redirect` sends
unauthenticated users to `/login` unless the location is in `publicPaths()` (`/`, `/login`,
`/user-guide`, and `/debug` in debug builds), and bounces non-instructors off `/instructor/*`.

Two `ShellRoute`s hold the tabbed areas — student (`/home`, `/schedule`, `/progress`,
`/profile`, plus `/training` and `/payments`) and instructor (`/instructor/home`,
`/collections`, `/reports`, `/settings`, where Settings is the role-aware Profile screen).
Everything else is a full-screen route. Roughly twenty instructor report drill-downs are
registered explicitly, three more (`activity`, `missing-invoice`, `fee-master`) through the
generic `_reportRoute` helper, and the old tournament Past/Upcoming paths redirect to the one
summary screen. `/competition` → `/tournament` keeps renamed links alive.
`developerRoutes()` registers `/debug` **only under `kDebugMode`** — that screen dumps the
bearer token. Every shell and the root router install a `LiveRefreshNavigatorObserver`, so
popping a dialog, the scanner or the checkout WebView triggers a refresh.

---

## 5. `lib/services/` — the client's real logic

### Networking core

**`api_service.dart`** (383) — the single HTTP chokepoint.
- `baseUrl` = `http://apimac.zyncbook.com`; `boostBaseUrl` = `https://apimacuat.zyncbook.com`,
  used **only** for `/Bcpg/*`, because those routes 404 on prod while UAT serves them against
  the same database. Both constants carry delete-me-when-shipped comments.
- `boostCertPem` pins UAT's self-signed Plesk certificate (expires 2027-04-17) and
  `trustsBadCertificate()` accepts it **only on that host**. Android's
  `network_security_config` alone was not enough — Dart's `HttpClient` never reads it, so
  every payment start died in the TLS handshake.
- `client` is an overridable `http.Client`, which is how tests and the screenshot tool serve
  canned responses. The comment explains the abandoned alternative (`HttpOverrides`) and
  exactly how it failed.
- Verbs: `get`, `post`, `put`, `delete`, `postMultipart` (with `sendEmptyFields`, repeated
  form-data parts for `InvoiceIds`, and byte uploads), `getBytes`, and `getPdfSmart` — which
  tolerates a PDF arriving as raw bytes, as base64, or inside a JSON wrapper with a URL.
- `_handle()` maps status codes to user-safe messages and, critically, **inspects the
  HTTP-200 error envelope** so a wrong password surfaces the server's own message.
- `sessionEpoch` increments on every token change; an in-flight request that crosses an epoch
  boundary is rejected with a 409 so a stale response cannot land in a new session.
- Request/response logging is `kDebugMode`-only (release logcat must not carry IC numbers).
- Web builds can route through a local CORS proxy via `--dart-define=WEB_API_PROXY=…`.

**`response_utils.dart`** (151) — the envelope helpers everything else leans on:
`unwrapData()` (an envelope with `meta` but no `data` unwraps to `null`, not to itself),
`findRecordList()` (dig a list out of any shape), `apiEnvelopeError()` /
`apiEnvelopeErrorCode()` (checks **both** `status` and `meta.code`, since a report can return
200 with `meta.code: 400`), `pickField()` / `pickAmount()`, and **`friendlyError()`** — the one
function standing between users and raw exception text. It maps network/auth/5xx errors, turns
a `FormatException` (a Wi-Fi captive portal answering with HTML) into a plain message, and
swallows anything that smells like a SQL or .NET stack trace.

**`api.dart`** (421) — typed wrappers for every Swagger endpoint, grouped by controller, with
URL encoding and the documented quirks baked in: `_reportBody()` fills the ±2-year window and
sends `reportType` as a **string**; `termPaymentQuery()` builds ASP.NET's repeated-param array
form; `profileUpdateProfile()` is multipart with `sendEmptyFields: true` so clearing a field
actually clears it. `profileNotificationDetails()` is present but carries a **DO NOT RENDER
THIS** warning — the route is not scoped to the caller and returned 32 rows naming 30
different students.

**`rn_api.dart`** (131) — a mirror of the React Native `api` object, so ported screens make the
same request and get the same shape. Includes RN's `defaultRange()` (last 18 months → end of
next year) and `numericReportType()` (nulls a non-numeric `reportType` for the two routes that
cast it to int).

**`api_changes.dart`** (32) — a broadcast stream of write topics. A successful write publishes
`attendance` / `booking` / `payments` / `profile` / `notifications` / `students`, which
invalidates live reads. Note the care: `/Attendance/Add` only emits when `data.status == 0`,
because a "select your class time" prompt is not a completed check-in.

### Session and storage

**`user_session.dart`** (1600) — the largest file in the app, a `ChangeNotifier` singleton
holding everything about the signed-in member.
- **Persistence split**: `splitAuthForStorage()` separates the bearer token (→ OS keystore via
  `SecureStore`) from the profile blob (→ SharedPreferences). `restoreSession()` also migrates
  any inline token left by an older build and rewrites the blob without it.
- **Login / logout / `switchBranch()`** — branch switching goes through
  `POST /Profile/UpdateToken/{branchId}` (not `/Account/ChangeClub`, which 400s for
  instructors), applies the new token and reloads every branch-scoped cache.
- **`switchStudent()` is a pure client-side filter.** `/Account/ChangeStudent` returns 400 for
  guardian credentials, so a guardian's login already carries every child's rows and picking a
  sibling just re-scopes them via `activeStudentName`.
- **Row scoping** — `scopeToSelf()` exists because `/Reports/Receipts`, `GradingSchedule` and
  `PaymentSlips` return the **whole branch** even for a student token. If nothing matches and
  the list holds several distinct people, it returns **empty** rather than leak someone else's
  receipts.
- **Money getters** — `dueAmount` and `invoiceCount` deliberately pick different sources by
  role: instructors trust the server-precomputed `HomePageStats` (their own), students trust
  the live outstanding rows (`HomePageStats` can lag or return 0). Both fall back through
  `_deepReadAmount` / `_deepReadCount`, which walk any response shape.
- **Field resolution** — `displayName`, `registrationNo`, `studentCode`, `phone`, `email`,
  `clubName` etc. all use `_pick()` across candidate key spellings, with a fuzzy last resort
  for `displayName` that explicitly skips club/centre/instructor/parent names.
- **`resolvePhotoUrl()`** — turns a relative or backslashed server path into a loadable URL.
  Requiring `http` used to drop every relative photo and fall through to the club crest.
- **Notification polling** — a 5 s timer with in-flight coalescing, a generation counter and an
  epoch check, so a response from a previous account can never be accepted.
- Also: the payment lock (2-minute client-side guard), the store-version banner comparison,
  local base64 photo cache (the API has no photo read-back), and grading-date derivation.

**`secure_store.dart`** (52) — `flutter_secure_storage` wrapper (Android
`encryptedSharedPreferences`, iOS Keychain `first_unlock`) with an in-memory fallback if the
platform channel throws. Documents why: the session used to be persisted whole, token
included, as plaintext prefs.

**`extra_trust.dart`** (34) — installs the bundled Sectigo R46 root into Dart's default
`SecurityContext` on Android. The photo host sends the leaf and DV R36 intermediate but not the
cross-signed root; Android 7–12 doesn't ship R46, so every photo failed and fell back to
initials. This is the v2.13.3 fix.

### Payments

**`boost_payment.dart`** (279) — the Boost gateway through the backend's `/Bcpg/*` routes.
Models `TermPayment`, `PurchaseItem` (field names `qty`/`price` verified against Swagger —
getting them wrong would bill a zero line), `PaymentIntent`, `PaymentStart`, `PaymentResult`.
`start()` **refuses to mix purchases with invoices**, because the server silently takes the
purchase path and the invoices are not demonstrably billed. `confirm()` is the heart of it:
it never guesses. It retries `VerifyPayment` (the callback can land after the user returns),
then reconciles by refetching outstanding invoices **for every account in the payment** — a
parent can pay for several children in one session — and returns `PaymentOutcome.unknown`
rather than report an unconfirmable success.

**`prepay_service.dart`** (152) — advance-month pricing. Models `PrepayMonth`, `PrepayQuote`,
`PrepayInvoice`, `PrepayBill`. The term-payment endpoint answers one (student, month) per call,
so both methods loop; `gatherInvoices()` counts `failedRequests` so a partial quote is never
labelled complete.

**`purchase_service.dart`** (169) — the gear catalogue. There is **no create-purchase route**:
a purchase is raised by paying for it, with the lines riding in `purchaseItems` on
`/Bcpg/PayInvoices`. Hence no `submit()`. Handles tolerant product parsing, basket totals
rounded to sen (3 × 33.33 must not bill 99.98999999999999), and `countRequests()` — the
before/after baseline that proves a payment created a request.

**`receipt_pdf.dart`** (316) — renders the official receipt client-side with `pdf`, because
`/Utilities/ReceiptAsPDF` returns a blank template for the ids the app can supply. Matches the
club's layout: `# | Student Name | Invoice Type | Description | Amount`, amount-in-words
(`RINGGIT MALAYSIA … SEN ONLY`, full English number speller included), total, payment mode.
`rowsForReceipt()` groups by `receiptNo` **across payers**, since one receipt can cover a batch
payment for several students.

**`autopay.dart`** (81) — Auto Pay as a Boost card/bank mandate. `AutoPayMethod`,
`AutoPayState` (off / pending / active / failed), `AutoPayMandate` with a `label` getter
("Visa •••• 4242"). **Three `TODO(api)` stubs**: `status()` returns `off`, `setup()` and
`cancel()` throw a clear message. Deliberate — guessing a URL would be worse than saying the
feature is not open yet.

### Attendance and booking

**`class_booking.dart`** (170) — the booking rules the server does not enforce. `isoDate()`
formats **local** time on purpose (UTC conversion rolls the date back a day in UTC+8, booking
an evening class for yesterday). `datesForDayOfWeek()` gives the student real dates to pick
from; `isAlreadyBooked()` / `takenDates()` / `preferredDate()` are the only thing preventing a
double booking, since `BookNow` accepts duplicates and mismatched weekdays. `bookNowBody()`
builds the one shape the server does validate (a non-empty `timeSlots`).

**`attendance_outcome.dart`** (62) — parses `/Attendance/Add`, which always answers HTTP 200.
`status: 0` recorded, `1` re-POST with a `tTimeId`, `-1` rejected, and an unparseable body maps
to `-2` with an honest "could not confirm" message.

**`manual_attendance.dart`** (72) — the *proposed* `/Attendance/MarkByInstructor` contract.
`isAvailable()` checks the server's live Swagger route table (cached) so the register UI
appears the moment the backend ships it, with no app update. `markPresent()` returns a result
for **every** requested student — one the server doesn't report on is "unconfirmed", never
assumed marked.

**`nfc_service.dart`** (151) — `nfc_manager` wrapper. A tag is "linked" by writing the
student's `ST-` code as an NDEF text record; there is no server-side registry, so reading a tag
posts the identical `/Attendance/Add` body as a QR scan. Write sessions verify by read-back.
Android-only by design; degrades quietly everywhere else.

### Notifications

**`notification_service.dart`** (321) — local OS notifications, because server push is
unverified: there is no dedicated push-token route, though the old app registered its device by
sending the FCM token as `DeviceId` at login, so "impossible" (as this file and
`ARCHITECTURE.md` used to say) was wrong — see the correction in `ARCHITECTURE.md`. Documents the Android 8+ rule that the *channel* owns sound and vibration
and is frozen at creation — so loudness is baked into the channel id
(`dclix-<category>-<alert|vibrate|quiet>-v1`) and channels are created lazily. `init()`
**never throws**: a failed plugin means a degraded app, not a screen stuck on a spinner
forever (which is exactly what happened). `alertForNew()` does the I/O; the selection logic is
the separately testable `planAlerts()`.

**`notification_prefs.dart`** (208) — `NotifCategory` (payments / classes / general),
`NotifPrefs` (master switch, sound, vibrate, per-category, quiet hours) with tolerant JSON
parsing, `inQuietHours()` (handles the midnight wrap; start == end is an *empty* window, not a
24-hour mute), and `categorise()` — which matches the **body** in **both English and Malay**,
because live rows always have an empty `notificationType` and their real content is Malay
(`"Sila jelaskan yuran tertunggak RM85.00…"`). Keying off `notificationType` filed everything
under "general".

**`notification_diff.dart`** (122) — `planAlerts()`, and the two RN bugs it exists to prevent:
(1) the volume cap must run **after** the category filter, or muting fees silences class
notices *and* advances the high-water mark past them; (2) quiet hours must **defer**, not
advance the mark, or "silence overnight" means "delete". A null `lastSeen` seeds the mark
without alerting, so a fresh sign-in isn't buried under a backlog.

**`background_poll.dart`** (124) — WorkManager job, ~15 min (Android's floor). The callback runs
in a **headless isolate**: no widgets, no providers, so it reads the token and member id back
from storage by hand. `backgroundCallbackDispatcher` carries
`@pragma('vm:entry-point')` — without it tree-shaking silently removes it from release builds.

**`live_refresh.dart`** (88) — `LiveRefreshMixin`: a 15 s data poll (5 s for messaging) that
skips when the app is backgrounded, when a screen is covered, or when a refresh is already in
flight, and also fires on `ApiChanges` topics. `LiveRefreshNavigatorObserver` emits
`navigation` on pop so a returned-to screen refreshes immediately. `LiveRefresh.enabled` is
flipped off for the whole test suite by `test/flutter_test_config.dart`.

### Messaging and misc

**`chat_store.dart`** (249) — a local echo of messages the member sent, because the backend
delivers a reply to the admin panel and exposes **no way to read it back**. Without this the
member's own messages vanished on close. `buildThread()` assembles a conversation from the
caller's **own** `MyNotifications` rows plus the echo — never from
`/Profile/NotificationDetails`. `buildThreadList()` groups into conversations and marks a
thread **not repliable** when it has no real `groupId`, since `Reply2Notification` answers 200
to any id and the message would be echoed then silently dropped.

**`online_submissions.dart`** (40) — the four proposed new-student endpoints. A 404 must render
"Awaiting backend", never an empty report.

**`web_download.dart` / `_stub.dart` / `_web.dart`** (7/7/17) — conditional-import facade for
browser downloads via Blob + anchor, because `printing`'s web `sharePdf` throws
`MissingPluginException`. The stub throws on native, which never calls it.

---

## 6. `lib/utils/`, `lib/data/`, `lib/theme/`

| File | Description |
|---|---|
| `utils/progress_stats.dart` (202) | All Progress/Belt maths, implementing the shared Codex spec. Belt tint lookup (only when exactly one colour word appears), `StudentIdentity` + `scopeStudentRows()` (self keeps anonymous rows; a *selected sibling* keeps positive matches only, because a guardian's token returns every child's rows and an anonymous one could be any of them), `countPeriod()`, `summarizeRecent()` (six-month chart, Monday-start week streak, and a `streakAtBoundary` flag when the streak runs past the fetched history). |
| `utils/qr_content.dart` (57) | The official code formats — `TC-` + 8 digits for a centre, `ST-` + 8 for a student — with a builder, a parser and a `label` for scan feedback. Same string is the `qrCode` field whether it came from a QR, an NFC tag or the marking list. |
| `utils/training_schedule.dart` (94) | Merges per-centre class times into one ordered list, because there is no all-centres route. Parses `"18:00 To 19:00 (Monday) - Normal training"` into a weekday (whole-word match on 3+ letter prefixes: mon/tues/thurs) and start minutes, honouring AM/PM. Sorts Mon→Sun, then time, then centre; day-less slots last. |
| `data/guide_content.dart` (300) | The 12-page user guide as data — `GuideStep` (icon, title, intro, numbered details, tips, a highlighted note, and an optional `shot` asset). **No API calls anywhere**, because the guide must work before sign-in. Pages: signin, home, checkin, schedule, booking, payments, autopay, notifications, alerts, chat, profile, everything. Only pages whose screen renders fully offline carry a screenshot — a picture of a loading state teaches nothing. |
| `theme/app_theme.dart` (279) | `AppColors` light/dark (orange `#F97316` on near-white / near-black), `Radii`, `Gaps`, `Shadows`, and the `ThemeData` builders. Exposes the palette as a `ThemeExtension` with `context.appColors` sugar. |
| `theme/ion.dart` (1368) | **Generated.** Every Ionicons glyph named exactly as in `@expo/vector-icons` 15.0.3, kebab-case → camelCase, Dart keywords suffixed (`Ion.switch_`). Do not hand-edit. |
| `theme/app_icons.dart` (112) | A smaller hand-curated alias map using Material-ish names (`AppIcons.home`, `AppIcons.chevron_left`) that resolve to Ionicons codepoints. |
| `theme/theme_provider.dart` (45) | Light/dark `ChangeNotifier`, seeded from the platform brightness, persisted to prefs, with a revision guard so a slow load can't clobber a user toggle. |

---

## 7. `lib/widgets/` — shared UI

| File | Description |
|---|---|
| `rn_kit.dart` (479) | Flutter counterparts of the RN primitives: `Touchable` (opacity press, no ripple), `HexAlpha` extension, `ErrorState` (inline "didn't load" + retry), `Skeleton` / `SkeletonRow` / `SkeletonList` / `SkeletonStatRow`, `Glass` (frosted blur), `RnCircleButton`, `safeBack()`, and `notify()` / `confirmDialog()`. |
| `report_kit.dart` (566) | Port of RN's `reportkit.tsx` — everything the instructor report and filter screens share: `ScreenHeader`, `RkLabel`, `SelectField` (bottom-sheet picker, searchable for long lists), `DateField` (month-calendar sheet), `toISODate()`, and the list scaffolding. |
| `premium_kit.dart` (356) | The "premium" style introduced with the redesigned profile: `PremiumTint` palette, `premiumCard` / `premiumSlate` decorations, `TintedIcon`, `PremiumHeader` (rounded orange gradient from the status bar down), `HeaderIconButton` with a badge, `SectionLabel`, `GroupCard` (inset dividers), `PremiumRow`, `PremiumTile`, `SlateGlow`. |
| `list_search.dart` (353) | Reusable search field + filter chip strip for list-heavy screens. `ListFilter` is either a picker (opens a bottom sheet) or a boolean toggle; chips show "All X" or "X: value" with a clear button, plus a result count. |
| `student_switcher.dart` (286) | The guardian's child picker, shared by Profile and the Home avatar. Fetches `/Listing/MySiblings`, offers an "All Students" aggregate, and applies the pick through `UserSession.switchStudent` — a client-side filter, no network. |
| `anim.dart` (247) | Motion kit. `Motion` curve/duration/stagger constants, `FadeSlideIn` (one-shot entrance, safe inside a `ListView`), `AnimatedCount` (tweened numbers for hero stats), `Shimmer` / `ShimmerList`. Respects the platform reduce-motion flag by rendering final state at zero duration. |
| `use_api.dart` (125) | Port of RN's `useApi`. `ApiResource<T>` keeps existing data on a failed fetch (a stale value plus a visible error beats a confident fake zero) and supersedes in-flight requests so a late old response can't overwrite newer state. The `UseApi` mixin disposes resources with the State and **refetches everything when `ApiService.sessionEpoch` changes** (sibling or branch switch). |
| `club_tab_bar.dart` (149) | The five-slot frosted bottom bar shared by both roles — four tabs plus the raised centre "Scan" button that pushes `/qr-scan` (or `/instructor/qr-scan`). Semantics set for selection and buttons. |
| `member_avatar.dart` (57) | Photo with an initials fallback. Prefers a locally cached base64 photo, then a `CachedNetworkImage`, then initials — and an empty student photo stays empty rather than falling back to the club logo. |
| `app_header.dart` (88) | Title/subtitle header with an optional back button that falls back to `/home` when there's nothing to pop. |
| `gradient_button.dart` (110) | The orange-gradient primary CTA — full width, loading spinner, optional trailing icon in a white circle. |
| `app_icon_button.dart` (34) | 42 pt circular icon button (an `InkWell` — which is why standalone routes need a `Material` ancestor; see the test). |

---

## 8. `lib/screens/` — 40 screens

### Shell and entry
- **`splash_screen.dart`** (139) — animates for at least 1.6 s so it never flickers, calls
  `restoreSession()`, then routes to the role's home or `/login`.
- **`login_screen.dart`** (705) — port of `login.tsx`. Student/Instructor toggle; instructors
  also enter a club code and pick a branch (`Api.accountGetBranchesByClubCode` → `_BranchSheet`).
  Password reveal, focus handling, a link to the user guide for people without an account.
  No server switcher — that was removed.
- **`tabs_shell.dart`** (17) / **`instructor_tabs_shell.dart`** (18) — `Scaffold` +
  `ClubTabBar`, hiding the bar when the keyboard is up.

### Student
| Screen | Data sources | Notes |
|---|---|---|
| `home_screen.dart` (696) | `homePageStats`, `myInfo` | Owns `kStudentQuickCards`, the 13-tile quick-access grid (icons/colours shared with `more_screen`). Dues card, Today's Class, news/offers, `QuickGrid`, `openRoute()`. Live-refreshing. |
| `schedule_screen.dart` (297) | `studentDetails` | Weekly timetable with per-session colours. |
| `progress_screen.dart` (350) | `attendanceReport` | Attendance rate over 30/90/365 days, classes this month, week streak, last class, six-month chart. Uses `progress_stats.dart`; no grading section because the route returns nothing for students. |
| `belt_rank_screen.dart` (195) | `myInfo` | The grade exactly as recorded, including sub-ranks. No belt journey — the API has no grade list. |
| `training_screen.dart` (310) | `myInfo`, `attendanceReport` | "My Trainer" / training info. |
| `attendance_screen.dart` (275) | `attendanceReport` | History; presence decided by the `attendanceType` string only. |
| `qr_scan_screen.dart` (436) | `attendanceAdd`, `myInfo`, `trainingTimeByTcId` | Camera check-in. Rejects obviously foreign payloads (`WIFI:`, `BEGIN:VCARD`, …) before hitting the API, then handles the three `/Attendance/Add` outcomes including the "pick your class time" re-POST. |
| `book_class_screen.dart` (475) | `TrainingTimeWithDateAndInstructor`, `BookNow`, `PackageInfo`, `getBookings`, `instructors`, `trainingCenters` | Month/day picker driven by `class_booking.dart`, since the timetable is weekly and the server accepts any date. |
| `payments_screen.dart` (1140) | `outstanding`, `receipts`, `FetchTermPayments`, `ReceiptAsPDF`, `mySiblings`, Boost | The big one: Pay / Prepay / History segments, sibling account switcher, selection cart, `_PaySheet`, `_PrepaySegment`, receipt download, and the Boost start/confirm round trip. |
| `outstanding_invoices_screen.dart` (267) | `outstanding`, `invoiceTypes`, Boost | "Pay Your Dues" — type filter, pending-only toggle, multi-select, pay. |
| `payment/term_payment_screen.dart` (458) | `mySiblings`, `PrepayService`, Boost | Pick year + months + which children; every resulting invoice itemised then totalled. |
| `payment/bcpg_webview_screen.dart` (186) | Boost | In-app WebView hosting the checkout page. `isMerchantReturn()` detects the redirect back; the caller still verifies — a redirect is never proof. |
| `autopay_screen.dart` (417) | `AutoPay` | Card-or-bank mandate UI. Takes its loader as a constructor seam so tests can render every state. |
| `purchase_request_screen.dart` (261) | `PurchaseService`, Boost | Catalogue with quantity fields; paying is what raises the request. |
| `purchases_screen.dart` (125) | `purchaseRequests` | Past requests; one appears only after its payment lands. |
| `profile_screen.dart` (1053) | `myInfo`, `myClubStats`, `mySiblings`, `QRCodeBytes`, branches | Role-aware (it is also the instructor Settings tab). Premium header, dark Member ID card with a full-screen QR, copyable registration/phone, quick actions, grouped details, theme toggle, branch/student switching, log out. |
| `edit_profile_screen.dart` (403) | `UpdateProfile` | Multipart edit form; identity fields are echoed back alongside the edits. |
| `student_details_screen.dart` (114) | `myInfo`, `studentAddtnlInfo` | Read-only particulars. |
| `chat_screen.dart` (211) | session notifications + `ChatStore` | Conversation list from notification groups merged with local echo. |
| `chat_thread_screen.dart` (315) | `Reply2Notification`, `Send2ClubHelpDesk`, `UpdateNotification2Read` | One conversation; opens read-only when the thread has no real `groupId`. |
| `notifications_screen.dart` (234) | `UpdateNotification2Read` | Inbox with relative timestamps. |
| `notification_settings_screen.dart` (325) | — | Master switch, sound/vibrate, per-category, quiet hours, and a **test alert** button. |
| `helpdesk_screen.dart` (169) | `Send2ClubHelpDesk` | Subject + message; the reply comes back as a new notification, not into a thread. |
| `events_screen.dart` (231) / `offers_screen.dart` (192) / `offer_detail_screen.dart` (193) | `homePageStats` | Events and offers live **inside** HomePageStats — there is no endpoint of their own, and every offer row's `id` is 0, so `code` is the identity. The detail screen doubles as the voucher shown at the counter and selects strictly by code. |
| `tournament_screen.dart` (306) | `TournamentSummary` | Medal and player totals only; `TournamentRow` documents the absent date/venue/status. |
| `more_screen.dart` (146) | — | The full feature catalogue, grouped (Training / Payments / …), a superset of the home grid. |
| `user_guide_screen.dart` (199) | — | Paged walkthrough over `kGuideSteps`. Works signed-out. |
| `debug_screen.dart` (234) | — | Pretty-prints the whole cached session with "Copy all JSON". **Debug builds only** — it shows the bearer token. |

### Instructor
| Screen | Notes |
|---|---|
| `instructor_home_screen.dart` (382) | Grouped quick-access tiles + club stats, dues from `outstanding`. |
| `instructor_collections_screen.dart` (295) | Collection counts by type (1 cash, 2 online/FPX, 3 bank-in slip), `UpdateCollectionCount`, plus the embedded `CollectionListScreen` drill-down. |
| `instructor_reports_screen.dart` (273) | `kInstructorReports` — the report catalogue as data, grouped into Centres & students / Classes & grading / Payments & finance. |
| `instructor_report_list_screen.dart` (828) | The generic drill-down: renders the filters a `ReportSpec` declares, fetches, filters client-side, renders cards. Includes `ApiCentres`. |
| `instructor_attendance_screen.dart` (546) | Class Check-In. Shows the class list and the centre QR (with a printable PDF / generated QR), and only reveals the tick-and-save register when `ManualAttendance.isAvailable()` says the route exists — so it never offers a Save that cannot work. |
| `new_student_screen.dart` (681) | Online-submission approvals + `StudentParticularsScreen`. A 404 renders "Awaiting backend"; never fabricated rows. |
| `instructor_reports/report_spec.dart` (215) | `RFilter`, `ReportQuery`, `ReportSpec`, `kReportSpecs`, and the per-report body builders — including the `/Reports/Receipts` rule that `reportType` may only be `Cash` or `FPX`. |
| `instructor_reports/rn_reports.dart` (1453) | Fourteen 1:1 ports of the RN `r-*.tsx` screens: student/training/exam centres, student list, training schedule, centre roster, grading, outstanding, attendance, receipts, purchase requests, payment slips, tournament, contribution, reimbursement. Each handles the documented server quirk the same way RN did. |
| `instructor_reports/student_detail_screen.dart` (542) | Per-student view built by filtering `/Outstanding/Fetch` and `/Reports/Receipts` on id/IC/name. |
| `instructor_reports/student_list_fetch.dart` (150) | Aggregates the real roster from `/Listing/StudentListByTcId` (one call per centre, in parallel) and enriches it from `/Outstanding/Fetch`. `/Reports/StudentDetails` is unusable here — for an instructor token it returns the instructor's own schedule rows. |

---

## 9. `test/` — 45 suites

Beyond ordinary unit tests, several suites guard classes of bug type-checking cannot catch.

**Structural / contract guards**
- `api_wiring_test.dart` — static audit: scans `lib/` for every `ApiService.<verb>('<path>')` and
  checks path *and* verb against `fixtures/club_api_routes.json` (the live 73-path route table).
- `screen_wiring_test.dart` — every screen must have a real data source, and screens with a
  specific contract must still call their endpoint. Also catches stale exemptions.
- `navigation_targets_test.dart` — every menu/grid tile must point at a registered route.
- `material_ancestor_test.dart` — a standalone route without a `Material` ancestor (an `InkWell`
  there crashes the screen).
- `loading_state_test.dart` — a screen must always be able to leave its loading state.
- `screen_render_test.dart` — render smoke tests for network-free screens (overflows, unbounded
  Columns, null-derefs in builders).
- `guide_content_test.dart` — the guide must not promise something the app doesn't do; no missing
  or orphaned screenshots; 12 distinct pages.
- `react_native_parity_test.dart` (555) — parity assertions against the Expo reference.
- `android_resources_test.dart` — resources referenced from XML must exist in a clean checkout.
- `ios_deployment_target_test.dart` — nothing below iOS 15 (Xcode 27 refuses it).
- `app_version_test.dart` — `kAppVersion`/`kAppBuild` must match `pubspec.yaml`.

**Security guards**
- `no_committed_credentials_test.dart` — no working password in any file. The repo is public and
  leaked accounts twice.
- `token_not_in_prefs_test.dart` — the bearer token must never reach SharedPreferences.
- `developer_routes_test.dart` — `/debug` must not exist in a release build.
- `boost_cert_pin_test.dart` *(new, untracked)* — the Dart client must accept exactly the pinned
  UAT certificate, and only on that host.
- `extra_trust_test.dart` — the R46 root is bundled and registered as an asset.

**Behaviour**
`boost_payment_test`, `purchase_service_test`, `prepay_service_test`, `prepay_bill_test`,
`class_booking_test`, `attendance_outcome_test`, `manual_attendance_test`, `qr_content_test`,
`training_schedule_test`, `progress_stats_test` (shared Codex spec cases), `chat_store_test`,
`notification_prefs_test`, `notification_delivery_test`, `notification_diff` coverage,
`background_poll_test`, `live_refresh_test`, `live_messaging_test`, `photo_url_test`,
`friendly_error_test`, `session_error_message_test`, `api_envelope_error_test`,
`is_instructor_test`, `current_student_id_test`, `switch_branch_token_test`,
`term_payment_query_test`, `report_spec_test`, `receipt_pdf_test`, `receipt_rows_test`,
`receipt_format_test`, `invoice_date_test`, `tournament_offers_test`, `profile_screen_test`,
`autopay_screen_test` *(new, untracked)*, `widget_test`.

**Opt-in / support**
- `live_api_smoke_test.dart` — probes every screen's endpoints against the **live** API and
  prints a wiring table. Skipped unless `--dart-define=LIVE_USER/LIVE_PASS` are supplied, so the
  default suite stays offline and no account is ever committed.
- `flutter_test_config.dart` — runs before every suite; disables `LiveRefresh` so ordinary
  render tests don't advance a live clock.
- `fixtures/club_api_routes.json` — the route table `api_wiring_test` checks against.

## 10. `tool/` — not part of `flutter test`

| File | Purpose |
|---|---|
| `capture_guide_shots.dart` (428) | Regenerates the user-guide screenshots: `flutter test tool/capture_guide_shots.dart --dart-define=CAPTURE=true`. Lives in `tool/` because `flutter test` auto-discovers `test/` and this writes to `assets/`. Renders the real screens deterministically at a fixed phone size with **no phone, no login and no real member's data** — the Expo guide once shipped a real name, phone number and member QR. |
| `fake_api.dart` (358) | The fixture behind it. Every value is invented; keeping it in source means a capture physically cannot contain anyone's record. Serves through the injectable `ApiService.client`. |
| `render_check.dart` (147) | Renders every guide screen under the same harness and reports OK or the exception, without writing images. |
| `probe_manual_attendance.dart` (133) | Live probe answering "can an instructor token record attendance for a student?" Read-only by default; `--dart-define=PROBE_WRITE=true` creates a **real** attendance record. Credentials via `--dart-define`, never committed. |

---

## 11. Platform folders

**`android/`** — `app/build.gradle.kts` sets `applicationId com.dclix.clubapp`, Java 17, core
library desugaring (needed for `flutter_local_notifications` on minSdk 24), and a release
signing config read from the gitignored `key.properties`, falling back to the debug key.
`AndroidManifest.xml` declares INTERNET, NFC (optional feature), POST_NOTIFICATIONS, VIBRATE,
`usesCleartextTraffic` and the network security config.
`res/xml/network_security_config.xml` allows cleartext (prod serves no HTTPS) and adds the UAT
self-signed certificate **for that host only**, with system CAs listed first so a proper
certificate just works.
`res/raw/keep.xml` protects `dclix_alert.wav` and `uat_apimacuat.pem` from resource shrinking —
the chime was silently stripped from a release APK because it's only resolved by name at
runtime, and notifications fell back to the system sound with no build error.
`MainActivity.kt` is the bare `FlutterActivity`. Plus launcher icons, launch backgrounds,
light/dark styles and the Gradle wrapper.

**`ios/`** — standard Runner with `AppDelegate.swift`, `SceneDelegate.swift`, storyboards,
`Info.plist` (display name "Club Management App") and a **`Podfile` post-install hook that
raises every pod's `IPHONEOS_DEPLOYMENT_TARGET` to 15.0** and never lowers one — Xcode 27
rejects anything below 15 and several plugin pods still declare 9.0–14.0. `RunnerTests.swift`
is the default stub. `Pods/`, `.symlinks/` and `Flutter/ephemeral/` are generated.

**`macos/`, `linux/`, `windows/`** — untouched Flutter desktop scaffolding (runners, CMake
files, generated plugin registrants, entitlements). Not targets the app ships to.

**`web/`** — `index.html` and `manifest.json` plus icons. The web build is a preview only: the
backend is plain HTTP with no CORS headers, so authenticated screens stay empty in a browser
unless the local proxy is running. The user guide works without an account.

## 12. `assets/`

`branding/` — app icon, adaptive foreground, logo, notification icon (sources for
`flutter_launcher_icons`).
`certs/sectigo_public_server_authentication_root_r46.pem` — the trust anchor `ExtraTrust`
installs.
`fonts/Ionicons.ttf` + its licence — byte-identical to Expo's, so `ion.dart`'s codepoints match.
`guide/*.png` — 12 generated guide screenshots (fictional data only).
`images/logo.png`, `sounds/dclix_alert.wav` — the notification chime, also duplicated into
`android/res/raw/`.

---

## 13. Working-tree state as of this write-up

> **Stale as of committing this file (2026-09-30).** Everything listed below has since
> landed: the Auto Pay work shipped in `flutter-v2.15.0`, and the old/new parity fixes
> (F1–F11) are on `main`. Sections 1–12 still describe the tree accurately; read this last
> section as a dated snapshot, not as the current state.

Uncommitted, on `main`, on top of `5d200fc` ("docs: design for Boost gateway on Due and Monthly
payments"): the **Auto Pay rewrite from a monthly reminder to a Boost card/bank mandate**.

- `lib/services/autopay.dart` — rewritten (−237/+…): the reminder scheduling is gone, replaced
  by the mandate model and the three `TODO(api)` stubs.
- `lib/screens/autopay_screen.dart` — rewritten (685 lines changed) for card/bank selection and
  the four mandate states.
- `lib/services/notification_service.dart` — −104: reminder scheduling removed; `init()` now
  cancels notification id `918001`, any Auto Pay reminder still pending from before the update.
- `lib/services/user_session.dart` (−56), `lib/services/api_service.dart` (+48, the Boost cert
  pin), `lib/data/guide_content.dart` + `assets/guide/autopay.png` (guide page rewritten and
  re-captured), `lib/screens/instructor_reports/rn_reports.dart` (−47).
- `pubspec.yaml`/`.lock` — one dependency dropped.
- `test/autopay_test.dart` **deleted**, replaced by the untracked
  `test/autopay_screen_test.dart`; `test/boost_cert_pin_test.dart` is also new and untracked.
  `guide_content_test`, `loading_state_test` and `screen_wiring_test` updated to match.
- `docs/diagrams/` — untracked generated architecture diagram and its visual checks.
