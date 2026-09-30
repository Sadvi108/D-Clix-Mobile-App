# Flutter live API verification — 2.12.1+19

## Implemented behavior

| Feature | Refresh and confirmation |
|---|---|
| Messaging / notification inbox | Fetch `/Profile/MyNotifications` every five seconds in the foreground; coalesce simultaneous requests; update open conversations and unread badges even if the unread count is unchanged. Retain drafts and reject responses from a previous account. |
| OS alerts | Local alerts from the fetched inbox. Empty first inbox seeds a zero high-water mark; denied permissions and failed delivery do not consume messages. Quiet hours defer alerts. Tap navigation handles cold launch and active app. |
| QR attendance | Only `data.status == 0` confirms a check-in. A class-time prompt, rejection, missing status or malformed envelope cannot report success. A repeated class-time prompt does not recursively reopen the picker. Confirmed changes invalidate attendance readers, and returning from the scanner refreshes history. |
| Visible API data | 15-second refresh, immediate resume refresh and refresh after navigation returns. Applies to dashboards, attendance/progress, training/schedule/booking data, profile/details, collections and reports, purchases, payment history, events and offers. |
| Forms and payments | Automatic refresh waits while invoices/cart items are selected or checkout is in progress. Background fetches keep content visible. Edit-profile and student-approval forms are not periodically reset. Checkout creation is never treated as payment confirmation. |
| Account isolation | API requests time out after 25 seconds and reject a response if the session token changed. Chat history is scoped to the authenticated user rather than the selected sibling. Request/response bodies are excluded from API debug logs. |

These are polling intervals, not guaranteed delivery deadlines: network latency, offline state and server availability affect freshness. Data refresh runs only for visible, active screens. The API does not expose a socket/message stream; outgoing replies remain a locally stored echo after server acceptance because no caller-scoped sent-message read-back contract exists.

## Live reads

Checked with user-supplied credentials kept exclusively in private temporary files. No passwords, bearer tokens, member payloads or real QR images are included in this repository.

| Account label | Successful API responses | Failure |
|---|---:|---|
| Student A | 23 / 24 | `/Outstanding/FetchTranxCharges`: HTTP 200 with error envelope status 400 |
| Student B | 23 / 24 | Same endpoint/error |
| Instructor, KCP branch | 29 / 30 | Same endpoint/error |

The matrix covers profile, club stats, inbox, unread count, bookings, home stats, training centres/instructors, invoice types, siblings, attendance, student details, grading, receipts, purchase requests, payment slips, tournament summary, outstanding/term/manual collection data and products. Student additional information and instructor collections/centre/reimbursement/contribution/activity reports are included for their respective roles. Successful API responses include empty datasets; this is not evidence that a live write or payment completed.

`FetchTranxCharges` is advertised with a multipart payment-model contract rather than a history-list contract. Its existing history call returns a backend error; Flutter now shows an unavailable state rather than “No receipts”. A correct caller-scoped charge-history endpoint/contract still needs clarification from the backend owner.

## Automated verification

- 298 tests passed; three opt-in live/credential tests skipped. The private authenticated read checks above ran separately.
- Static analysis: no errors or warnings; informational style/deprecation lints remain.
- Tests cover same-count message arrivals, open-conversation updates preserving a draft, failure/recovery, account-switch races, no overlapping refreshes, lifecycle pause/resume, hidden routes, return navigation, QR success-only invalidation, denied OS permission and notification-delivery retries.
- The parity screenshot harness covers 22 fictional-data screens per theme. See `react-native-parity-audit.md` for the earlier visual work and its limits.

Run `flutter test` and `flutter analyze --no-fatal-infos` from `flutter_app/`. CI repeats both and builds the release-mode test APK, verifies packaged chime/public-certificate resources and publishes a checksum.

## Still requires backend or device verification

1. **Instant push while closed is not implemented** (and is unverified rather than impossible — the previous Xamarin app registered its device by sending the FCM token as `DeviceId` on `/Account/Authenticate`, so the backend has somewhere to store one; see the F9 correction in `ARCHITECTURE.md`). Production Swagger exposes 69 paths and UAT 73; neither inspected document advertises device registration, an FCM/APNs sender or a message-stream contract. The supplied UAT Swagger location is an API document, not backend source or Firebase configuration. See [FCM Flutter setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started) and [message handling](https://firebase.google.com/docs/cloud-messaging/flutter/receive-messages). Backend work must register authenticated device tokens, handle rotation/logout, send to the intended member, and supply Android/iOS Firebase configuration before device delivery can be tested.
2. **Background polling is delayed fallback.** Android WorkManager has a minimum 15-minute periodic interval; actual execution is OS-controlled, may be delayed and does not run for a force-stopped app. See [Android periodic work](https://developer.android.com/develop/background-work/background-tasks/persistent/getting-started/define-work). It is not an alternative implementation of immediate push.
3. **No live message send or attendance write was performed.** Sending to staff and creating an attendance record require the pending explicit authorization. No connected Android device/emulator was available for physical camera, permission, background or force-stop testing. Unit/widget checks do not prove those device behaviors.
4. **Online checkout remains blocked by the UAT certificate configuration.** Strict TLS validation rejects the host; trusting a bundled public certificate alone does not repair a missing hostname SAN. No certificate bypass was introduced. The backend needs a valid host certificate or production `/Bcpg` routes.
5. **New-student approval contracts remain undeployed** in the inspected API. The app reports that backend dependency. Auto Pay remains a reminder with manual payment confirmation, as already documented in the parity audit.
6. **Signing:** no original production keystore was supplied or configured in repository Actions secrets. The downloadable APK is explicitly a debug-signed test prerelease. A production-compatible update cannot be promised until the original signing key is supplied.
