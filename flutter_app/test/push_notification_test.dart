import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/notification_service.dart';
import 'package:dclix_app/services/push_notification_service.dart';
import 'package:dclix_app/services/secure_store.dart';
import 'package:dclix_app/services/user_session.dart';

// Fictional values only: nothing here is a real account or notification.
const _userId = 90002;
const _mark = 'dclix.notif.lastSeen.v1.$_userId';
const _ledger = 'dclix.notif.delivered.v1';

PushPayload _push(Map<String, dynamic> data) => PushPayload.parse(data);

Map<String, dynamic> _row(int id) =>
    {'id': id, 'text': 'Fictional notice', 'value': 'Sample body'};

http.Response _ok(Object? data) =>
    http.Response(jsonEncode({'status': 200, 'data': data}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final shown = <int?>[];
  final shownPayloads = <String?>[];
  final pluginCalls = <String>[];
  final identities = <String>[];
  var forgotten = 0;
  var cleared = 0;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    NotificationService.resetForTest();
    PushNotificationService.resetForTest(ready: true);
    PushNotificationService.isSignedIn = () => true;
    PushNotificationService.refreshFromServer = () {};
    identities.clear();
    forgotten = 0;
    cleared = 0;
    PushNotificationService.identify = (id) async => identities.add(id);
    PushNotificationService.forget = () async => forgotten++;
    PushNotificationService.clearShown = () async => cleared++;
    await SecureStore.delete(UserSession.tokenKey);
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    shown.clear();
    shownPayloads.clear();
    pluginCalls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel,
        (call) async {
      pluginCalls.add(call.method);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return {'notificationLaunchedApp': false};
        case 'areNotificationsEnabled':
          return true;
        case 'show':
          final args = call.arguments as Map;
          shown.add(args['id'] as int?);
          shownPayloads.add(args['payload'] as String?);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    NotificationService.resetForTest();
    NotificationService.onTap = null;
    PushNotificationService.resetForTest();
    debugDefaultTargetPlatformOverride = null;
    binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  group('payload parser', () {
    test('reads every legacy key', () {
      final p = PushPayload.parse({
        'dclix_id': '4021',
        'title': 'Leave request',
        'body': 'Approve absence?',
        'click_action': 'request',
        'dclix_type_id': '3',
        'unread_count': '7',
      });
      expect(p.id, '4021');
      expect(p.osId, 4021);
      expect(p.title, 'Leave request');
      expect(p.body, 'Approve absence?');
      expect(p.isRequest, isTrue);
      expect(p.sourceTypeId, 3);
      expect(p.unreadCount, 7);
      expect(p.route, 'notifications');
    });

    test('falls back to the notification block and normalises the action', () {
      final p = PushPayload.parse(
        {'dclix_id': 'abc-9', 'click_action': '  ReQuest '},
        notificationTitle: 'From OS',
        notificationBody: 'Body from OS',
      );
      expect(p.title, 'From OS');
      expect(p.body, 'Body from OS');
      expect(p.isRequest, isTrue);
      expect(p.id, 'abc-9', reason: 'non-numeric ids still deduplicate');
      expect(p.osId, isNull);
      expect(
          PushPayload.parse({'dclix_id': '1', 'notificationType': 'request'})
              .isRequest,
          isTrue);
    });

    test('never invents an actionable type', () {
      final p = PushPayload.parse({'dclix_id': '12', 'title': 'Class moved'});
      expect(p.action, isNull);
      expect(p.isRequest, isFalse);
      expect(p.route, 'chat');
      expect(
          PushPayload.parse({'dclix_id': '12', 'click_action': 'message'})
              .isRequest,
          isFalse);
    });

    test('malformed and hostile input degrades to a safe, id-less payload', () {
      for (final data in <Map<String, dynamic>>[
        {},
        {'dclix_id': 'null', 'unread_count': '-4', 'dclix_type_id': 'x'},
        {'dclix_id': '1 OR 1=1', 'unread_count': '9999999999'},
        {'dclix_id': '../../etc', 'unread_count': 'many'},
        {'dclix_id': 'a' * 65},
        {
          'dclix_id': ['5'],
          'title': {'nested': true}
        },
      ]) {
        final p = PushPayload.parse(data);
        expect(p.id, isNull, reason: '$data');
        expect(p.osId, isNull);
        expect(p.unreadCount, isNull);
        expect(p.route, 'notifications', reason: 'safe list, never a guess');
      }
      expect(PushPayload.parse({'dclix_id': '99999999999'}).osId, isNull,
          reason: 'does not fit an OS notification id');
    });
  });

  group('delivery and deduplication', () {
    Future<void> seedMark() =>
        NotificationService.alertForNew(userId: _userId, rows: []);

    test('push first: the next poll of the same id stays quiet', () async {
      await seedMark();
      await PushNotificationService.handleForeground(
          _push({'dclix_id': '5', 'title': 'Hello', 'body': 'World'}));
      expect(shown, [5]);
      expect(shownPayloads, ['chat']);

      await NotificationService.alertForNew(userId: _userId, rows: [_row(5)]);
      expect(shown, [5]);
      expect((await SharedPreferences.getInstance()).getInt(_mark), 5,
          reason: 'the mark still advances past the push-delivered row');
    });

    test('poll first: a later push for the same id stays quiet', () async {
      await seedMark();
      await NotificationService.alertForNew(userId: _userId, rows: [_row(6)]);
      expect(shown, [6]);
      await PushNotificationService.handleForeground(_push({'dclix_id': '6'}));
      expect(shown, [6]);
    });

    test('foreground alerts once and routes a request to its actions',
        () async {
      final p = _push({'dclix_id': '8', 'click_action': 'request'});
      await Future.wait([
        PushNotificationService.handleForeground(p),
        PushNotificationService.handleForeground(p),
      ]);
      expect(shown, [8]);
      expect(shownPayloads, ['notifications']);
    });

    test('signed out or id-less pushes raise nothing locally', () async {
      var refreshed = 0;
      PushNotificationService.refreshFromServer = () => refreshed++;
      await PushNotificationService.handleForeground(_push({'title': 'No id'}));
      expect(shown, isEmpty, reason: 'the poll alerts it, with dedup');
      expect(refreshed, 1, reason: 'but the list still refreshes');

      PushNotificationService.isSignedIn = () => false;
      await PushNotificationService.handleForeground(_push({'dclix_id': '11'}));
      expect(shown, isEmpty);
    });

    test('a suppressed push alert is handed back to the poll', () async {
      await seedMark();
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async => switch (call.method) {
                'initialize' => true,
                'areNotificationsEnabled' => false,
                _ => null,
              });
      await PushNotificationService.handleForeground(_push({'dclix_id': '12'}));
      expect(await NotificationService.claimDelivery('12'), isTrue,
          reason: 'permission was off, so the id was released');
    });

    test('a tap while signed out records nothing', () async {
      PushNotificationService.handleOpened(_push({'dclix_id': '21'}));
      await pumpEventQueue();
      expect((await SharedPreferences.getInstance()).getStringList(_ledger),
          isNull);
      expect(await NotificationService.claimDelivery('21'), isTrue);
    });

    test('a tap while signed in records the id so the poll stays quiet',
        () async {
      await seedMark();
      await SecureStore.write(UserSession.tokenKey, 'fictional-bearer');
      PushNotificationService.handleOpened(_push({'dclix_id': '22'}));
      await pumpEventQueue();
      await NotificationService.alertForNew(userId: _userId, rows: [_row(22)]);
      expect(shown, isEmpty);
      await SecureStore.delete(UserSession.tokenKey);
    });

    test('the next account is not muted by the previous one\'s ids', () async {
      const nextUser = 90003;
      await PushNotificationService.handleForeground(_push({'dclix_id': '30'}));
      expect(shown, [30]);

      await PushNotificationService.signedOut();
      expect((await SharedPreferences.getInstance()).getStringList(_ledger),
          isNull,
          reason: 'persisted ledger cleared');

      await NotificationService.alertForNew(userId: nextUser, rows: []);
      await NotificationService.alertForNew(userId: nextUser, rows: [_row(30)]);
      expect(shown, [30, 30], reason: 'memory ledger cleared too');
    });

    test('markSeen advances the mark without alerting', () async {
      await NotificationService.markSeen(
          userId: _userId, rows: [_row(3), _row(9), _row(4)]);
      expect(shown, isEmpty);
      expect((await SharedPreferences.getInstance()).getInt(_mark), 9);
      await NotificationService.markSeen(userId: _userId, rows: [_row(2)]);
      expect((await SharedPreferences.getInstance()).getInt(_mark), 9,
          reason: 'never moves backwards');
    });

    test('polling keeps raising alerts until push is switched on', () {
      expect(PushNotificationService.serverPushLive, isFalse);
      expect(PushNotificationService.alertsViaPush, isFalse);
    });
  });

  test('the push channel\'s group is created before the channel', () async {
    // Android rejects a channel whose group does not exist yet, which left
    // existing_android_channel_id pointing at nothing until the first local alert.
    await NotificationService.ensurePushChannel();
    final group = pluginCalls.indexOf('createNotificationChannelGroup');
    final created = pluginCalls.indexOf('createNotificationChannel');
    expect(group, isNonNegative);
    expect(created, greaterThan(group));
  });

  test('the Android channel the backend names is the one the app creates', () {
    // Backend contract: existing_android_channel_id (docs/push-notifications.md).
    expect(NotificationService.pushChannelId, 'dclix-general-alert-v1');
  });

  test('only a server-assigned subscription id counts as registered', () {
    for (final id in [null, '', 'local-1234']) {
      expect(PushNotificationService.isServerSubscriptionId(id), isFalse,
          reason: '$id');
    }
    expect(
        PushNotificationService.isServerSubscriptionId(
            '1c3c1b0e-0000-4000-8000-000000000000'),
        isTrue);
  });

  test('registration check never touches OneSignal when push is off', () {
    PushNotificationService.resetForTest();
    var called = false;
    PushNotificationService.whenRegistered(() => called = true);
    expect(called, isFalse);
  });

  group('taps', () {
    test('cold-start tap is held until the app takes it, then opens once', () {
      PushNotificationService.handleOpened(
          _push({'dclix_id': '13', 'click_action': 'request'}));
      var wakes = 0;
      NotificationService.onTap = () => wakes++;
      expect(wakes, 1, reason: 'installing the handler reports the held tap');
      expect(NotificationService.takeHeldTap(), 'notifications');
      expect(NotificationService.takeHeldTap(), isNull, reason: 'opens once');
    });

    test('malformed payload opens only the safe list', () {
      PushNotificationService.handleOpened(
          _push({'dclix_id': '<script>', 'click_action': ''}));
      expect(NotificationService.takeHeldTap(), 'notifications');
    });
  });

  group('a held tap never crosses accounts', () {
    late http.Client original;
    var unauthorized = false;

    setUp(() {
      original = ApiService.client;
      unauthorized = false;
      ApiService.client = MockClient((request) async {
        if (unauthorized) return http.Response('', 401);
        if (request.url.path == '/Account/Authenticate') {
          return _ok({'id': 20, 'userType': 3, 'accessToken': 'fictional-b'});
        }
        return _ok([]);
      });
    });

    tearDown(() {
      UserSession.instance.logout();
      ApiService.client = original;
    });

    Future<void> storeSessionOfMemberA({bool withProfile = true}) async {
      await SecureStore.write(UserSession.tokenKey, 'fictional-a');
      if (withProfile) {
        SharedPreferences.setMockInitialValues({
          UserSession.sessionKey: jsonEncode({'id': 10, 'userType': 3}),
        });
      }
    }

    void tapPushOfMemberA() {
      PushNotificationService.handleOpened(
          _push({'dclix_id': '50', 'click_action': 'request'}));
      expect(NotificationService.hasHeldTap, isTrue);
    }

    Future<bool> memberBSignsIn() => UserSession.instance
        .login(username: 'member-20', password: 'fictional', userType: 3);

    test('stale token: restore fails (401), member B signs in, nothing opens',
        () async {
      await storeSessionOfMemberA();
      tapPushOfMemberA();
      unauthorized = true;
      expect(await UserSession.instance.restoreSession(), isFalse);
      expect(NotificationService.hasHeldTap, isFalse);

      unauthorized = false;
      expect(await memberBSignsIn(), isTrue);
      expect(NotificationService.takeHeldTap(), isNull);
      expect(forgotten, 1, reason: 'the expired session also unlinked push');
    });

    test('token outlived its profile (iOS reinstall): dropped with the tap',
        () async {
      await storeSessionOfMemberA(withProfile: false);
      tapPushOfMemberA();
      expect(await UserSession.instance.restoreSession(), isFalse);
      expect(NotificationService.hasHeldTap, isFalse);
      await pumpEventQueue();
      expect(await SecureStore.read(UserSession.tokenKey), isNull,
          reason: 'an orphaned bearer token must not count as signed in');

      expect(await memberBSignsIn(), isTrue);
      expect(NotificationService.takeHeldTap(), isNull);
    });

    test('a tap held at the login screen is dropped by a manual sign-in',
        () async {
      tapPushOfMemberA();
      expect(await memberBSignsIn(), isTrue);
      expect(NotificationService.takeHeldTap(), isNull);
    });

    test('a restored session keeps its tap and opens it once', () async {
      await storeSessionOfMemberA();
      tapPushOfMemberA();
      expect(await UserSession.instance.restoreSession(), isTrue);
      expect(NotificationService.takeHeldTap(), 'notifications');
    });
  });

  group('identity', () {
    late http.Client original;

    setUp(() {
      original = ApiService.client;
      ApiService.client = MockClient((request) async {
        final path = request.url.path;
        if (path == '/Account/Authenticate' || path == '/Account/ChangeClub') {
          return _ok({
            'id': 10,
            'userType': 3,
            'accessToken': 'fictional-bearer',
            'clubId': 1,
            'clubList': [
              {'id': 1, 'value': 'NORTH', 'text': 'North Academy'},
            ],
          });
        }
        return _ok([]);
      });
    });

    tearDown(() {
      UserSession.instance.logout();
      ApiService.client = original;
    });

    Future<bool> signIn() => UserSession.instance
        .login(username: 'member-10', password: 'fictional', userType: 3);

    test('external id separates account kinds and rejects junk', () {
      expect(PushNotificationService.externalIdFor({'id': 10, 'userType': 3}),
          '3-10');
      expect(
          PushNotificationService.externalIdFor({'id': '10', 'userType': '0'}),
          '0-10');
      for (final auth in <Map<String, dynamic>?>[
        null,
        {},
        {'id': 10},
        {'userType': 3},
        {'id': 0, 'userType': 3},
        {'id': 'x', 'userType': 3},
      ]) {
        expect(PushNotificationService.externalIdFor(auth), isNull,
            reason: '$auth');
      }
    });

    test('sign-in and club switch bind the device to the member', () async {
      expect(await signIn(), isTrue);
      await pumpEventQueue();
      expect(identities, ['3-10']);
      expect(
          await UserSession.instance.switchClub(
              clubId: 1,
              clubCode: 'NORTH',
              username: 'member-10',
              password: 'fictional'),
          isTrue);
      await pumpEventQueue();
      expect(identities, ['3-10', '3-10']);
    });

    test('a failing OneSignal login never blocks sign-in', () async {
      PushNotificationService.identify = (_) async => throw Exception('down');
      expect(await signIn(), isTrue);
    });

    test('logout unbinds the device and drops held taps and the ledger',
        () async {
      expect(await signIn(), isTrue);
      await PushNotificationService.handleForeground(_push({'dclix_id': '40'}));
      PushNotificationService.handleOpened(_push({'dclix_id': '41'}));

      UserSession.instance.logout();
      await pumpEventQueue();

      expect(forgotten, 1);
      expect(cleared, 1, reason: 'previous member\'s pushes and badge cleared');
      expect(await NotificationService.claimDelivery('40'), isTrue);
      expect(NotificationService.hasHeldTap, isFalse,
          reason: 'nothing opens for the next member');
    });

    test('a failing OneSignal logout does not break sign-out', () async {
      PushNotificationService.forget = () async => throw Exception('offline');
      await expectLater(PushNotificationService.signedOut(), completes);
    });

    test('push disabled: no OneSignal calls at all', () async {
      PushNotificationService.resetForTest();
      PushNotificationService.identify = (id) async => identities.add(id);
      PushNotificationService.forget = () async => forgotten++;
      PushNotificationService.clearShown = () async => cleared++;
      await PushNotificationService.signedIn({'id': 10, 'userType': 3});
      await PushNotificationService.signedOut();
      await PushNotificationService.clearBadge();
      expect(identities, isEmpty);
      expect(forgotten, 0);
      expect(cleared, 0);
    });
  });
}
