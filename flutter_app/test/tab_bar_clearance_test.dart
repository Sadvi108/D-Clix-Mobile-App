// Manual QA 2026-09-29: on Fees & Payments the pay bar floated a bar-height above the bottom
// tab bar, with an empty gap between them.
//
// The tab shells use Scaffold(extendBody: true), which already puts the tab bar's full height
// (62 + safe-area inset) into the body's MediaQuery.padding.bottom. Every tab screen then
// added the bar's 62 again (`62 + MediaQuery.paddingOf(context).bottom`), so anything placed
// at that height sat 62dp too high.
//
// Driven through the app's real routes and shell, with a gesture-bar inset.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/router/app_router.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';
import 'package:dclix_app/widgets/club_tab_bar.dart';

http.Response _ok(Object? data) => http.Response(jsonEncode({'status': 200, 'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late http.Client original;

  setUp(() {
    original = ApiService.client;
    SharedPreferences.setMockInitialValues({});
    final s = UserSession.instance;
    s.authData = {'id': 1, 'studentId': 1, 'userType': 3, 'name': 'Test Member'};
    s.myInfo = {'name': 'Test Member', 'studentId': 1};
    s.activeStudentId = null;
    s.activeStudentName = null;
    ApiService.client = MockClient((req) async => req.url.path == '/Outstanding/Fetch'
        ? _ok([
            {'id': 892521, 'studentId': 1, 'studentName': 'Test Member',
             'invoiceDescription': 'Monthly fee for June-2025', 'dueAmount': 50},
          ])
        : _ok([]));
  });

  tearDown(() {
    ApiService.client = original;
    UserSession.instance.stopNotificationPolling();
  });

  Future<void> open(WidgetTester tester, String location) async {
    // 800dp wide (the test font draws every glyph a full em wide) with a 34dp gesture bar.
    tester.view.physicalSize = const Size(2400, 2700);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(bottom: 102);
    addTearDown(tester.view.reset);

    final router = GoRouter(initialLocation: location, routes: appRouter.configuration.routes);
    addTearDown(router.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UserSession.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await _settle(tester);
  }

  double tabBarTop(WidgetTester tester) => tester.getRect(find.byType(ClubTabBar)).top;

  testWidgets('the Fees pay bar sits right on top of the tab bar, no gap', (tester) async {
    await open(tester, '/payments');
    await tester.tap(find.text('Monthly fee for June-2025'));
    await _settle(tester);

    final payBar = find.ancestor(of: find.text('1 selected'), matching: find.byType(Positioned));
    expect(tester.getRect(payBar).bottom, moreOrLessEquals(tabBarTop(tester)));
  });

  testWidgets("the Schedule's Book a class button floats one gap above the tab bar", (tester) async {
    await open(tester, '/schedule');

    final button = find.ancestor(of: find.text('Book a class'), matching: find.byType(Positioned));
    expect(tester.getRect(button).bottom, moreOrLessEquals(tabBarTop(tester) - Gaps.md));
  });
}
