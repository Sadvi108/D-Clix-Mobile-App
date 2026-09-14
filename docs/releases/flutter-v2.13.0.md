Flutter 2.13.0 (build 21), package `com.dclix.clubapp`. This release ports every React Native (Expo v2.11.1) screen to Flutter 1:1 and is the first release from the `D-Clix-Mobile-App` repository.

- Every screen is now a direct port of the Expo app: same layout, icons, copy, API calls and edge-case handling. This covers login, home (student and instructor), schedule, training, payments, profile, events/offers, competition, help desk, attendance, progress, purchases, book a class, chat, notifications, QR check-in, user guide, collections, class check-in, new student registration, pay your dues and all fourteen reports.
- Kept from the previous Flutter build: reminder-based Auto Pay, the Activities / Fee Master / Missing Invoice reports, payment lock, live refresh, secure token storage and notifications.
- Notification summaries respect the per-category preferences set in Notification Settings.
- iOS: minimum iOS version is now 14.0, and QR scanning uses Apple Vision (mobile_scanner 7.4.2). The iOS app builds and runs on Apple Silicon simulators.

**Verification and limits**

Automated checks on CI: 298 tests passed; three opt-in live/credential tests skipped. Static analysis reports no errors or warnings (60 info-level lints).

Refresh is still foreground REST polling, not instant background push. Online payment remains blocked by the UAT server certificate configuration. New-student approval routes still require backend deployment. See `docs/releases/flutter-v2.12.1.md` and `docs/realtime-verification.md` for details that still apply.

**Installation:** The APK is a release-mode **debug-signed test build**. It is not a production-signed upgrade; its key may differ from earlier downloads. Preserve needed local app data before replacing an existing installation. A compatible production update requires the original signing keystore. The attached SHA-256 file verifies the downloaded bytes.
