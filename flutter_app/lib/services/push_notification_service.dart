import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';

import 'notification_diff.dart';
import 'notification_service.dart';
import 'secure_store.dart';
import 'user_session.dart';

/// One push message in the legacy D-CLIX shape.
///
/// The Xamarin app read six data keys in three places (`App.xaml.cs:136-143,190-197,
/// 214-221`): `dclix_id`, `title`, `body`, `click_action`, `dclix_type_id` and
/// `unread_count`. This is the one tolerant parser for all of them. It never invents an
/// actionable type: without `click_action` (or the server row's `notificationType`) a
/// message is an ordinary notice, and a malformed id is no id at all.
class PushPayload {
  /// `dclix_id`, or null when missing or not a plain identifier. Kept as text so a
  /// non-numeric id still deduplicates exactly.
  final String? id;
  final String title;
  final String body;

  /// `click_action`, trimmed and lower-cased. `request` carries Accept/Reject.
  final String? action;

  /// `dclix_type_id`: source/type metadata only.
  final int? sourceTypeId;

  /// `unread_count` when it is a sane non-negative number.
  final int? unreadCount;

  const PushPayload({
    required this.id,
    required this.title,
    required this.body,
    this.action,
    this.sourceTypeId,
    this.unreadCount,
  });

  static final _plainId = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  factory PushPayload.parse(
    Map<String, dynamic> data, {
    String? notificationTitle,
    String? notificationBody,
  }) {
    String? text(Object? v) {
      final s = v?.toString().trim() ?? '';
      return s.isEmpty || s.toLowerCase() == 'null' ? null : s;
    }

    int? number(Object? v) => int.tryParse(text(v) ?? '');

    final id = text(data['dclix_id']);
    final unread = number(data['unread_count']);
    return PushPayload(
      id: id != null && _plainId.hasMatch(id) ? id : null,
      title: text(data['title']) ?? text(notificationTitle) ?? '',
      body: text(data['body']) ?? text(notificationBody) ?? '',
      action:
          text(data['click_action'] ?? data['notificationType'])?.toLowerCase(),
      sourceTypeId: number(data['dclix_type_id']),
      unreadCount:
          unread != null && unread >= 0 && unread < 100000 ? unread : null,
    );
  }

  /// The legacy keys travel in OneSignal's `data` (the SDK's `additionalData`).
  factory PushPayload.fromOneSignal(OSNotification n) => PushPayload.parse(
        n.additionalData ?? const {},
        notificationTitle: n.title,
        notificationBody: n.body,
      );

  bool get isRequest => action == 'request';

  /// Tap destination, in the payload vocabulary `main.dart` already routes. A request
  /// must land on the list that carries Accept/Reject; anything without a usable id falls
  /// back to that same safe list rather than guessing.
  String get route => isRequest || id == null ? 'notifications' : 'chat';

  /// An OS notification id: the server id when it fits, so a push alert and a poll alert
  /// for the same row would replace each other rather than stack.
  int? get osId {
    final n = int.tryParse(id ?? '');
    return n != null && n > 0 && n <= 0x7fffffff ? n : null;
  }

  /// Shaped like a `Profile/MyNotifications` row so the poll's title, body and category
  /// rules apply unchanged.
  Map<String, dynamic> get asRow => {
        'id': id,
        'text': title,
        'value': body,
        'notificationType': action ?? ''
      };
}

/// OneSignal push on top of the existing REST polling.
///
/// `Profile/MyNotifications` stays the source of truth; a push is a delivery signal plus
/// enough data to alert and route. The device is bound to the signed-in member through
/// OneSignal's external ID ([externalIdFor]); the backend sends to that ID, and
/// `OneSignal.logout()` on sign-out unbinds the phone, so the next person to use it never
/// receives the previous member's notices. See `docs/push-notifications.md`.
class PushNotificationService {
  /// Public by design: OneSignal app ids ship inside every client. Override per build
  /// with `--dart-define=ONESIGNAL_APP_ID=...`; an empty value disables push entirely.
  static const appId = String.fromEnvironment('ONESIGNAL_APP_ID',
      defaultValue: 'effd15e0-373e-4981-b319-ea22407d2a56');

  /// Set (`--dart-define=DCLIX_PUSH_LIVE=true`) only once the backend sends every
  /// notification through OneSignal. Until then polling raises the alerts exactly as
  /// before; after it, an opted-in device takes its alerts from push and polling only
  /// refreshes the list, so nothing is announced twice.
  static const serverPushLive = bool.fromEnvironment('DCLIX_PUSH_LIVE');

  static bool _ready = false;
  static bool get isAvailable => _ready;

  @visibleForTesting
  static Future<void> Function(String externalId) identify = OneSignal.login;
  @visibleForTesting
  static Future<void> Function() forget = OneSignal.logout;
  @visibleForTesting
  static Future<void> Function() clearShown = OneSignal.Notifications.clearAll;
  @visibleForTesting
  static bool Function() pushOptedIn = _oneSignalOptedIn;
  @visibleForTesting
  static bool Function() isSignedIn = _sessionSignedIn;
  @visibleForTesting
  static void Function() refreshFromServer = _refreshSession;

  static bool _oneSignalOptedIn() =>
      OneSignal.Notifications.permission &&
      (OneSignal.User.pushSubscription.optedIn ?? false);

  static bool _sessionSignedIn() => UserSession.instance.isLoggedIn;

  static void _refreshSession() {
    if (UserSession.instance.isLoggedIn) {
      unawaited(UserSession.instance.refreshNotifications());
    }
  }

  /// Bring up OneSignal and wire both message paths. NEVER THROWS.
  static Future<void> init() async {
    if (_ready || kIsWeb || appId.isEmpty) return;
    if (defaultTargetPlatform != TargetPlatform.android &&
        defaultTargetPlatform != TargetPlatform.iOS) {
      return;
    }
    try {
      // Verbose SDK logs while developing only; release builds stay quiet.
      if (kDebugMode) await OneSignal.Debug.setLogLevel(OSLogLevel.verbose);
      // onesignal:managed v1 — Codex-connected D-Clix; FCM uses Firebase d-clix.
      await OneSignal.initialize(appId).timeout(const Duration(seconds: 5));
      OneSignal.Notifications.addForegroundWillDisplayListener((event) {
        // Our own alert instead: club channel, sound, mutes, quiet hours, dedup.
        event.preventDefault();
        unawaited(
            handleForeground(PushPayload.fromOneSignal(event.notification)));
      });
      OneSignal.Notifications.addClickListener((event) =>
          handleOpened(PushPayload.fromOneSignal(event.notification)));
      _ready = true;
      unawaited(NotificationService.ensurePushChannel());
    } catch (e) {
      debugPrint('push unavailable, polling only: ${e.runtimeType}');
    }
  }

  @visibleForTesting
  static void resetForTest({bool ready = false}) {
    _ready = ready;
    identify = OneSignal.login;
    forget = OneSignal.logout;
    clearShown = OneSignal.Notifications.clearAll;
    pushOptedIn = _oneSignalOptedIn;
    isSignedIn = _sessionSignedIn;
    refreshFromServer = _refreshSession;
  }

  /// True when push, not polling, should raise this device's alerts.
  // ponytail: decided at sign-in/restore; a permission change mid-session applies at the
  // next one. A remote flag would make the switch-over instant if one is ever approved.
  static bool get alertsViaPush => serverPushLive && _ready && pushOptedIn();

  /// A push subscription id OneSignal's servers assigned. The SDK uses a `local-`
  /// placeholder until the device has registered.
  static bool isServerSubscriptionId(String? id) =>
      id != null && id.isNotEmpty && !id.startsWith('local-');

  /// Call [onRegistered] once, when this device has a real OneSignal push subscription.
  /// Checks immediately too: the id may already be assigned before the observer attaches.
  static void whenRegistered(void Function() onRegistered) {
    if (!_ready) return;
    var done = false;
    void check(String? id) {
      if (done || !isServerSubscriptionId(id)) return;
      done = true;
      onRegistered();
    }

    OneSignal.User.pushSubscription
        .addObserver((state) => check(state.current.id));
    check(OneSignal.User.pushSubscription.id);
  }

  // ── Identity ───────────────────────────────────────────────────────────────

  /// OneSignal external ID for a session: `<userType>-<id>`, e.g. `3-1234`. The type is
  /// part of it because students (3) and instructors (0/2) are separate account kinds and
  /// their ids are not known to be unique across kinds. Null when either is missing.
  static String? externalIdFor(Map<String, dynamic>? auth) {
    final id = int.tryParse('${auth?['id'] ?? ''}');
    final type = int.tryParse('${auth?['userType'] ?? ''}');
    if (id == null || id <= 0 || type == null || type < 0) return null;
    return '$type-$id';
  }

  /// Bind this device to the member who just signed in, restored or switched club.
  /// Bounded and best-effort: push must never hold up the session.
  static Future<void> signedIn(Map<String, dynamic>? auth) async {
    final externalId = externalIdFor(auth);
    if (!_ready || externalId == null) return;
    try {
      await identify(externalId).timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('push login failed: ${e.runtimeType}');
    }
  }

  /// The OS permission prompt, through OneSignal when it is up so its subscription
  /// sees the answer; the plain local-notification request otherwise.
  static Future<bool> requestPermission() async {
    if (!_ready) return NotificationService.requestPermission();
    try {
      return await OneSignal.Notifications.requestPermission(false);
    } catch (_) {
      return NotificationService.requestPermission();
    }
  }

  /// Drop shown pushes and the iOS app-icon badge the backend set (`ios_badgeCount`).
  /// The local-notification plugin can clear the tray but not that badge.
  static Future<void> clearBadge() async {
    if (!_ready) return;
    try {
      await clearShown().timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  /// Sign-out or an expired session: unbind the device, and forget everything the
  /// previous member's pushes left behind, including the badge on the app icon.
  static Future<void> signedOut() async {
    NotificationService.clearHeldTap();
    await NotificationService.clearDelivered();
    if (!_ready) return;
    try {
      await forget().timeout(const Duration(seconds: 5));
    } catch (e) {
      debugPrint('push logout failed: ${e.runtimeType}');
    }
    await clearBadge();
  }

  // ── Delivery ───────────────────────────────────────────────────────────────

  /// App in the foreground: OneSignal's own banner is suppressed, so raise exactly one
  /// local alert. In the background OneSignal shows the notification itself.
  static Future<void> handleForeground(PushPayload p) async {
    // Signed out: never show a notice meant for a member who is not here.
    if (!isSignedIn()) return;
    refreshFromServer();
    // No id means no way to deduplicate against the poll, which will alert the row itself.
    final id = p.id;
    if (id == null || !await NotificationService.claimDelivery(id)) return;
    final row = p.asRow;
    final ok = await NotificationService.present(
      title: titleOf(row),
      body: bodyOf(row),
      category: categoryOf(row),
      id: p.osId,
      payload: p.route,
      badge: p.unreadCount,
    );
    // Muted, quiet hours or no permission: give the id back so the poll decides later.
    if (!ok) await NotificationService.releaseDelivery(id);
  }

  /// A tap on a push. Routing waits in `main.dart` until a member is signed in; nothing
  /// is accepted or rejected from here.
  static void handleOpened(PushPayload p) {
    final id = p.id;
    // Recorded only for a signed-in device, so a previous member's ids can never hide
    // the next member's alerts.
    if (id != null) {
      unawaited(_hasStoredSession().then((signedIn) =>
          signedIn ? NotificationService.claimDelivery(id) : null));
    }
    refreshFromServer();
    NotificationService.deliverTap(p.route);
  }

  static Future<bool> _hasStoredSession() async {
    final token = await SecureStore.read(UserSession.tokenKey);
    return token != null && token.isNotEmpty;
  }
}
