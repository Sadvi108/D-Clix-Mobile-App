import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/screens/chat_screen.dart';
import 'package:dclix_app/screens/chat_thread_screen.dart';
import 'package:dclix_app/theme/ion.dart';

Map<String, dynamic> row(int id, String body) => {
      'id': id,
      'groupId': 'test-group',
      'text': 'Club update',
      'value': body,
      'isRead': true,
      'notifyDate': '2026-09-12T09:00:00'
    };
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final session = UserSession.instance;
  late http.Client old;
  setUp(() {
    old = ApiService.client;
    SharedPreferences.setMockInitialValues({});
    session.stopNotificationPolling();
    session.authData = {'id': 90001};
    session.acceptNotifications([]);
    ApiService.setToken('fictional-test-token');
  });
  tearDown(() {
    session.stopNotificationPolling();
    session.authData = null;
    session.acceptNotifications([]);
    ApiService.clearToken();
    ApiService.client = old;
  });

  test('changed content arrives even when unread count stays the same',
      () async {
    var rows = [row(1, 'First version')];
    var requests = 0;
    ApiService.client = MockClient((request) async {
      expect(request.url.path, '/Profile/MyNotifications');
      requests++;
      return http.Response(jsonEncode({'data': rows}), 200);
    });
    await session.refreshNotifications();
    final revision = session.notificationsRevision;
    final unread = session.unreadNotifications;
    rows = [row(2, 'New version')];
    await session.refreshNotifications();
    expect(requests, 2);
    expect(session.unreadNotifications, unread);
    expect(session.notificationsRevision, greaterThan(revision));
    expect(session.notifications!.single['value'], 'New version');
  });

  test(
      'concurrent refreshes share one request and stale account results are ignored',
      () async {
    final response = Completer<http.Response>();
    var calls = 0;
    ApiService.client = MockClient((_) {
      calls++;
      return response.future;
    });
    final a = session.refreshNotifications(),
        b = session.refreshNotifications();
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    session.authData = {'id': 90002};
    ApiService.setToken('fictional-next-token');
    response.complete(http.Response(
        jsonEncode({
          'data': [row(1, 'Old account')]
        }),
        200));
    await Future.wait([a, b]);
    expect(session.notifications, isEmpty);
    expect(session.notificationsError, isNull);
  });

  test('transient failure keeps messages and a later refresh recovers',
      () async {
    session.acceptNotifications([row(1, 'Keep this message')]);
    ApiService.client =
        MockClient((_) async => http.Response('Service unavailable', 503));
    await session.refreshNotifications();
    expect(session.notifications!.single['value'], 'Keep this message');
    expect(session.notificationsError, isNotNull);
    ApiService.client =
        MockClient((_) async => http.Response('{"data":[]}', 200));
    await session.refreshNotifications();
    expect(session.notifications, isEmpty);
    expect(session.notificationsError, isNull);
  });

  testWidgets(
      'open conversation updates incoming messages without clearing a draft',
      (tester) async {
    var rows = [row(1, 'First incoming message')];
    ApiService.client = MockClient(
        (request) async => http.Response(jsonEncode({'data': rows}), 200));
    await tester.pumpWidget(
        const MaterialApp(home: ChatThreadScreen(threadKey: 'test-group')));
    await tester.pumpAndSettle();
    expect(find.text('First incoming message'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Unsent draft');
    rows = [...rows, row(2, 'Second incoming message')];
    await session.refreshNotifications();
    await tester.pumpAndSettle();
    expect(find.text('Second incoming message'), findsOneWidget);
    expect(find.text('Unsent draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'sending preserves a newer draft and refresh does not duplicate the echo',
      (tester) async {
    final accepted = Completer<http.Response>();
    ApiService.client = MockClient((request) async {
      if (request.url.path == '/Profile/Reply2Notification')
        return accepted.future;
      return http.Response(
          jsonEncode({
            'data': [row(1, 'Existing message')]
          }),
          200);
    });
    await tester.pumpWidget(
        const MaterialApp(home: ChatThreadScreen(threadKey: 'test-group')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'First outgoing');
    await tester.tap(find.byIcon(Ion.send));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'Next draft');
    accepted.complete(http.Response('{"status":200,"data":true}', 200));
    await tester.pumpAndSettle();
    await session.refreshNotifications();
    await tester.pumpAndSettle();
    expect(find.text('First outgoing'), findsOneWidget);
    expect(find.text('Next draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Chat Academy list reflects a sent help-desk message on return',
      (tester) async {
    ApiService.client = MockClient((request) async {
      if (request.url.path == '/Profile/Send2ClubHelpDesk') {
        return http.Response('{"status":200,"data":true}', 200);
      }
      return http.Response('{"status":200,"data":[]}', 200);
    });
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const ChatScreen()),
      GoRoute(
          path: '/notification/:group',
          builder: (_, state) => ChatThreadScreen(
              threadKey: state.pathParameters['group']!,
              title: state.uri.queryParameters['t'] ?? 'Conversation')),
    ]);
    addTearDown(router.dispose);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Club · Help Desk'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Please call me');
    await tester.tap(find.byIcon(Ion.send));
    await tester.pumpAndSettle();
    router.pop();
    await tester.pumpAndSettle();

    expect(find.text('You: Please call me'), findsOneWidget);
  });
}
