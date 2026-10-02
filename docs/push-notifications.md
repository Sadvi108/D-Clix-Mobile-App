# Push notifications (OneSignal)

> **Provider:** the app owner chose OneSignal on 2026-10-02. They uploaded the Firebase service-account key to OneSignal and asked for the integration using OneSignal's Flutter guide. The legacy app and the old backend contract were direct FCM (`DeviceId` on Authenticate). The backend has not yet sent anything through OneSignal; see "Still to do outside the repo".
>
> **Rollout:** Android and basic iOS push registration are configured. `docs/onesignal-ios.patch` is a historical draft for adding the optional iOS Notification Service Extension. Do not apply it wholesale now: basic push entitlements, background mode, and signing are already configured. The draft contains:
> - the push and App Group entitlements;
> - `UIBackgroundModes`;
> - the OneSignal Notification Service Extension target, linking `OneSignalExtension` 5.5.1;
> - the CI signing change.

Status: **Android configuration migrated to the Codex-connected account on 2026-10-02.**
- OneSignal app: **D-Clix**, `effd15e0-373e-4981-b319-ea22407d2a56`.
- Organization: **Raig Technologies Sdn Bhd**, `60f5cabc-e845-4a07-a16b-1c77fa40762e`.
- Firebase project: **d-clix**, sender ID `364847542144`.
- The target app's Android SDK configuration reports FCM live with that exact sender ID.
- `.firebaserc` selects `d-clix` for Firebase tooling. There is no separate Firebase client SDK integration to replace: OneSignal uses the Firebase credentials server-side.
- Android debug APK builds; the changed Dart files pass analysis, and all 60 push/delivery/preference tests pass.
- The existing emulator installation was upgraded without clearing its app data. OneSignal confirms the new emulator subscription belongs to this app, is `AndroidPush`, is enabled, and has `notification_types: 1`.
- The subscription's external ID matches the restored signed-in member. This was read back through the Codex OneSignal connection.
- The user’s dashboard test at 15:34 was received by the Android emulator. OneSignal reports one successful Android dispatch with no errors, and the device log records the matching message ID `d531db43-bbd8-4953-9658-a9bba30e4323`. A screenshot at 15:45 shows “Hello there! 👋” in the notification tray. Android background delivery and visible tray display are verified.
- Android notification permission is granted and Do Not Disturb is off. The dashboard test omitted a category and used `fcm_fallback_notification_channel` at Android importance 3 (sound/tray, no heads-up banner). The existing `dclix-general-alert-v1` channel has importance 5 and the club sound. For dashboard tests that should show banners, use Android settings → Category → (Created in App) → Existing Channel: `dclix-general-alert-v1`. Production sends already specify this channel in the example below. A new remote push using that channel has not yet been observed.

iOS configuration and registration verified on 2026-10-02:
- The user saved a new APNs key in OneSignal for bundle `com.raigtech.dclix`. The dashboard reports Apple iOS Active with `.p8` authentication.
- Apple Developer lists Key ID `935F6G79TD`, Team ID `4Z59DEGJEZ`, Team Scoped (All topics), Sandbox & Production. The key remains outside the repository; its contents are not committed.
- Debug, Release, and Profile use the push entitlement and automatic signing through the existing Flutter xcconfigs. `Info.plist` enables `remote-notification` background mode.
- An Xcode simulator build succeeded. Its generated simulated entitlements contain `application-identifier: 4Z59DEGJEZ.com.raigtech.dclix` and `aps-environment: development`; the built plist includes `remote-notification`.
- The app was installed and launched on the Apple-silicon Mac's iPhone 17 Pro simulator without clearing app data. Apple issued an APNs token, and OneSignal confirms an enabled `iOSPush` subscription with `notification_types: 31`.
- The user sent an iOS dashboard test at 15:28 on 2026-10-02. OneSignal's message readback reports `successful: 1`, `errored: 0`, `failed: 0`, with the iOS platform successful count 1. The simulator's `willPresentNotification` log confirms the message arrived.
- That test's `data` was empty. D-Clix was foregrounded, so its existing handler called `preventDefault`; `handleForeground` skipped the local alert without a usable `dclix_id` (and also requires a signed-in member). The notification was received but no banner was shown. Settings was opened to background D-Clix for the user's next targeted dashboard test. No agent test push has been sent.
- The user's second dashboard test at 15:34 reported `successful: 2`, `errored: 0`, `failed: 0`: one iOS and one Android dispatch. A simulator screenshot at 15:35 shows its “Hello there! 👋” notification card on the lock screen, with the matching subtitle and body. **iOS background delivery and visible lock-screen display are verified.** The simulator was locked, so the visible alert was a lock-screen card. Foreground dashboard tests remain subject to the intentional handler behavior described above; Android tray display has now also been verified, as recorded above.
- The Notification Service Extension and App Group remain optional follow-up work for rich media and confirmed device receipt. A signed physical-device/App Store archive has not been validated locally.

Actual dashboard push delivery is verified on both simulators: iOS lock-screen display and Android notification-tray display. The Android test used a normal-importance fallback channel; a remote heads-up banner through the existing club channel remains unverified. No agent test sends have occurred. The app registers with OneSignal app **D-Clix** (`effd15e0-373e-4981-b319-ea22407d2a56`) and links each signed-in member to their device.

Polling still raises every alert: every 5 s in the foreground, plus WorkManager on Android. That stays true until the backend sends through OneSignal **and** a build with `DCLIX_PUSH_LIVE=true` ships.

## How it works in the app

| Piece | Where |
|---|---|
| Payload parser (`dclix_id`, `title`, `body`, `click_action`, `dclix_type_id`, `unread_count`, read from OneSignal `data`) | `PushPayload` in `lib/services/push_notification_service.dart` |
| Android early initialization (`DClixApplication`, native app ID from the same Dart build defines) | `android/app/src/main/kotlin/com/dclix/clubapp/DClixApplication.kt`, `android/app/build.gradle.kts` |
| OneSignal start-up before `runApp` (never throws; 5 s limit; an empty app id disables it) | `PushNotificationService.init`, `lib/main.dart` |
| Device ↔ member link: `OneSignal.login("<userType>-<id>")` after sign-in, session restore and club switch | `PushNotificationService.signedIn` / `externalIdFor` |
| Sign-out or expired session: `OneSignal.logout()`, then clear the delivered-id ledger, any held tap, shown pushes and the iOS badge | `PushNotificationService.signedOut` |
| Badge: foreground alerts carry `unread_count`; opening Notifications clears tray and badge | `NotificationService.present`, `PushNotificationService.clearBadge` |
| Foreground: OneSignal's banner is suppressed; one local alert goes through the existing channel, sound, mutes and quiet hours | `handleForeground` → `NotificationService.present` |
| Tap → route: `request` → `/notifications`; a notice with a valid id → `/chat`; malformed → `/notifications` | `handleOpened` → `NotificationService.deliverTap` → `main.dart` |
| Push/poll deduplication by `dclix_id` | `NotificationService.claimDelivery` (bounded ledger, cleared on sign-out/expiry) |
| Who raises alerts: push or polling, never both | `PushNotificationService.alertsViaPush`, `UserSession._armAlerts` |

Rules the code follows:

- **External ID format** is `<userType>-<id>` from the Authenticate response, e.g. `3-1234`.
  - Students/parents are type 3; instructors are 0 or 2.
  - The type is included because ids are not known to be unique across account kinds.
- `Profile/MyNotifications` is the source of truth. Every push triggers a refresh.
- **Deduplication:** each `dclix_id` alerts at most once. A push without a usable id raises no alert itself; the poll alerts that row.
- **Signed out:** the app shows and records nothing.
  - `OneSignal.logout()` switches the device to an anonymous user straight away.
  - The server-side unlink is a queued operation that the SDK saves on the device and retries. This was checked in the Android SDK 5.10.2 classes `LogoutHelper`, `LoginUserOperation` and `OperationModelStore`; iOS was not inspected.
  - Until that operation reaches OneSignal (for example, the phone was offline at sign-out), a push sent to the previous member can still arrive. While the app is in the background, the OS will show it.
  - **This is a residual account-isolation risk.** Direct FCM `deleteToken()` has the same offline window.
  - Mitigations: OneSignal pushes stay generic (see the Identity verification blocker below). On Android, an optional OneSignal Notification Service Extension can suppress display while signed out. iOS cannot suppress a visible push on the device.
- **Actions:** Accept/Reject never runs from a notification. It runs only from the in-app list (`notifications_screen.dart`).
- **Taps:** a tapped push or local alert is held in one place (`NotificationService`) and opens once, but only for a **restored** session.
  - A failed restore, a manual sign-in or a sign-out drops it, because whoever signs in next may not be the member it was for.
  - A keystore token without its profile blob (iOS keeps the Keychain across a reinstall) is deleted, not treated as a session.
- **`DCLIX_PUSH_LIVE`:**
  - Unset (the default): polling raises alerts exactly as before.
  - Set, and the device opted in: push is the alert path and WorkManager is cancelled. The foreground poll only refreshes the list and moves the high-water mark forward (`NotificationService.markSeen`).

## SDK

`onesignal_flutter` **5.5.2**, pinned exactly, from OneSignal's release list (`https://onesignal.github.io/sdk-releases/releases.json`, Stable channel). It bundles Android core 5.8.0 and iOS XCFramework 5.5.1. Upgrade only from that list, and keep the version in the iOS patch's `OneSignal-XCFramework` `exactVersion` in step with it.

Debug builds only:
- the SDK logs verbosely;
- `PushVerification.install` (`lib/services/push_verification.dart`), called after the first frame in `DClixApp.initState`, requests permission and logs a real subscription ID once;
- the observer also logs opt-in changes and immediately checks the current subscription to avoid a registration race;
- no setup-success dialog appears. A subscription alone is not proof of delivery.

Release builds skip the helper. Members are asked for permission after sign-in, as before.

## Native setup (in the repo)

- **Android:** OneSignal brings its own FCM plumbing; no Firebase client SDK or `google-services.json` is needed for this integration.
- **Migration startup:** the Android manifest uses `DClixApplication`. It initializes OneSignal in `Application.onCreate` before Flutter starts. The Gradle build reads `ONESIGNAL_APP_ID` from Flutter's Base64-encoded Dart build defines, falling back to the same public default as Dart, and emits `BuildConfig.ONESIGNAL_APP_ID`. The native dependency is pinned to `com.onesignal:OneSignal:5.8.0`, matching `onesignal_flutter` 5.5.2.
  - This fixes an observed upgrade failure: native SDK background startup reused the old saved app ID before Dart initialized, so Dart's new ID was ignored and the returned subscription still belonged to the disabled old app.
  - The fixed build was tested on the same installation: it created a new target-app subscription while preserving the member session and existing app data.
  - OneSignal App IDs are public. No REST key, FCM token or service-account private key is built into the APK.
- **Android channel fix:** the club alert channel names the group `dclix-notifications`, which was never created, so Android refused the channel (`NotificationChannelGroup doesn't exist`). Local alerts survived through a plugin fallback, but `existing_android_channel_id: "dclix-general-alert-v1"` pointed at nothing until the first local alert. The group is now created first, and a test pins the order.
- **iOS:** `Runner/Runner.entitlements` enables development APNs; App Store export selects the production environment. `Debug.xcconfig` and `Release.xcconfig` set `CODE_SIGN_ENTITLEMENTS`, `DEVELOPMENT_TEAM = 4Z59DEGJEZ`, and automatic signing. Profile already uses Release.xcconfig. `Info.plist` enables `remote-notification`.
  - No additional Firebase client SDK or native OneSignal initialization was added; the existing Flutter SDK owns initialization.
  - Simulator verification used `xcodebuild` with signing enabled. Xcode puts simulator push entitlements into the generated `Runner.app-Simulated.xcent` and the simulator executable; `codesign -d --entitlements` alone showed an empty dictionary and was not a sufficient simulator check. Apple token issuance and the OneSignal subscription confirmed registration.
  - **Optional extension:** the historical `docs/onesignal-ios.patch` drafts `OneSignalNotificationServiceExtension`, App Group `group.com.raigtech.dclix.onesignal`, OneSignalExtension 5.5.1, and CI signing. Adapt only the extension-specific pieces if adding it; create the target in Xcode and register the extension App ID/App Group under the same Apple team.

## Still to do outside the repo

1. **OneSignal dashboard → D-Clix → Settings → Push & In-App.** Never commit either file.
   - **Google Android (FCM): already configured for the target app.** Its public `android_params` returns sender ID `364847542144`, matching Firebase `d-clix`. No new service-account key was created or uploaded during migration.
   - **Apple iOS (p8): configured for the current bundle.** The user replaced the previous developer's key and saved Key ID `935F6G79TD` for `com.raigtech.dclix`, under Team `4Z59DEGJEZ`. The saved dashboard reports Apple iOS Active with `.p8` authentication and the matching bundle. The user authorized moving OneSignal away from the published old bundle `com.macsystem.app` even if that app loses push delivery. A different bundle requires a separate App Store listing; the user has been informed.
2. **Backend (Club.Api).** Keep the OneSignal **REST API key** on the server only. Wherever a member notification is created, send the request below. This is the full form, **only for after step 3 is solved**; until then use step 3's generic form:

   ```http
   POST https://api.onesignal.com/notifications?c=push
   Authorization: Key <REST API key>
   Content-Type: application/json

   {
     "app_id": "effd15e0-373e-4981-b319-ea22407d2a56",
     "target_channel": "push",
     "include_aliases": { "external_id": ["3-1234"] },
     "headings": { "en": "<title>" },
     "contents": { "en": "<body>" },
     "data": {
       "dclix_id": "<notification row id>",
       "title": "<title>",
       "body": "<body>",
       "click_action": "request or empty",
       "dclix_type_id": "<source type id>",
       "unread_count": "<member's unread count>"
     },
     "existing_android_channel_id": "dclix-general-alert-v1",
     "ios_sound": "dclix_alert.wav",
     "ios_badgeType": "SetTo",
     "ios_badgeCount": 3
   }
   ```

   - `dclix_id` **must** be the same id `Profile/MyNotifications` returns. Otherwise deduplication against polling fails.
   - Sending to an external ID that has no device is harmless.
   - Member notices go **only** to `include_aliases.external_id`. Never send them to segments such as "Total Subscriptions": a signed-out device is still a subscriber, and the OS shows whatever arrives.
3. **Identity verification (release blocker): unsolved in this SDK, so pushes must be generic.**
   The external ID (`3-1234`) is guessable, and the OneSignal app id ships in every APK. Any modified client can call `login("3-1234")` and receive that member's pushes. OneSignal's fix, Identity Verification, cannot be used from this app as built:
   - **Flutter SDK (evidence):** `onesignal_flutter` 5.7.0, the newest on pub.dev (published 2026-09-23), marks `loginWithJWT` `@Deprecated('Do not use, this method is not implemented…')`.
     - Its Dart body only calls native code on Android, so on iOS it returns **without authenticating**.
     - The Dart API has no way to refresh an expired JWT or to listen for one.
   - **Native SDKs (evidence):** the APIs exist one layer down.
     - iOS (OneSignalXCFramework 5.7.0): `login(externalId:token:)`, `onJwtExpired(expiredHandler:)`.
     - Android (OneSignal core 5.10.2): `IUserJwtInvalidatedListener` and an `updateUserJwt` path.
     - A custom bridge on both platforms is technically possible. It is **not** built here, and should not be built speculatively: the plugin maintainer says the feature is not implemented, and it cannot be verified end to end without three missing pieces:
       - a backend endpoint that issues per-member JWTs;
       - Identity Verification enabled in the OneSignal dashboard;
       - device tests on both platforms.
     - Turning Identity Verification on before every client sends a JWT would break login for all of them.

   **Rule until this is solved:** OneSignal pushes carry **no member-specific content**:
   - `headings`/`contents`: generic, e.g. "D-CLIX" / "You have a new notification".
   - `data`: only `dclix_id` (needed for deduplication) and `click_action` (needed so request alerts open the Accept/Reject list).
   - Never send `title`, `body`, `unread_count` or `ios_badgeCount`.

   The app shows the real content from the authenticated `Profile/MyNotifications`. Both the parser and tap routing already work with this reduced payload. The send example in step 2 shows the full payload for the day identity is verified; **until then, use the generic form above**.
4. **Switch-over, in this order.** Builds from before OneSignal never register with it, so they never get pushes and never see duplicates. The risk is only to OneSignal builds:
   - Builds **without** `DCLIX_PUSH_LIVE` still poll. A push the OS shows in the background is not recorded on the device (OneSignal has no Dart background hook), so the next poll alerts it again.
   - Builds **with** the flag stop polling alerts on opted-in phones. If the backend is not sending yet, those phones get nothing.
   1. Backend sends only to an allowlist of test external IDs. Verify on test phones running a build with `--dart-define=DCLIX_PUSH_LIVE=true`.
   2. Turn on backend sending for everyone, then release a build with the flag right away. Add it to both CI build commands. Until members update, OneSignal builds without the flag may show some notices twice. That is better than silence.

## Android dashboard test channel

In the Push Message Composer’s Android settings, select **Category → (Created in App)** and set **Existing Channel** to `dclix-general-alert-v1`. The installed app already creates this channel with high importance and the club sound. Omitting the category uses OneSignal’s default Miscellaneous channel, which normally shows sound/tray notifications without a heads-up banner. Android preserves a channel’s importance after creation; sending with a different channel avoids changing the member’s existing settings. See [OneSignal Android notification categories](https://documentation.onesignal.com/docs/en/android-notification-categories).

Keep the app in the background for a generic dashboard test; foreground messages follow D-Clix’s signed-in and `dclix_id` checks.

## Visible pushes vs. data-only

OneSignal sends visible notifications, with title and body, that the OS displays when the app is in the background.

- **Background:** per-category mutes and quiet hours are **not** applied. The OS shows the push before any Dart code runs.
- **Foreground:** all app preferences apply, because the app shows the alert itself.

Applying preferences in every app state needs the backend to store them and filter before sending. Data-only (silent) pushes are not a reliable alternative: iOS throttles them, and drops them after a force-quit. The app never adds a local alert on top of one the OS has already shown.

## Still to verify on physical devices

- [ ] Android 13+ and iOS: allow and deny the permission prompt
- [ ] The subscription appears in OneSignal under the right external ID
- [ ] Delivery in foreground, background and terminated states
- [ ] Tap routing
- [ ] Sound and channel
- [ ] Badge: `ios_badgeCount` sets it, and Notifications screen / sign-out clear it (`OneSignal.Notifications.clearAll`)
- [ ] Sign-out and account switch on one device: no pushes for the previous member
- [ ] Reinstall
- [ ] Known limits: force-stop on Android, swipe-away on iOS
- [ ] iOS: OneSignal and `flutter_local_notifications` share the notification-centre delegate (scene-based app). Check that taps on both push and local alerts route.

Once a device is subscribed, a single test can go to one test account's external ID from the OneSignal dashboard or the connector.

## Migration rollback

The pre-migration files, including unfinished user changes, were backed up to `/private/tmp/dclix-push-before-20261002-133914`. To undo only this migration, run:

```sh
python3 /private/tmp/dclix-push-before-20261002-133914/restore.py
```

The script checks that the migration files have not changed again before restoring them. It preserves earlier work and removes only the newly created migration files. Local `.onesignal/` checkpoint state is retained; do not commit it after rollback. Do not use a blanket `git restore`, because the push work was already uncommitted before this migration.
