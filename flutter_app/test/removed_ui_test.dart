// Removed at the club's request (2026-09-29): the Home "Featured Offers" carousel and the
// sign-in screen's "New to D-Clix? Contact your academy" line.
//
// Every value here is invented.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/data/guide_content.dart';
import 'package:dclix_app/screens/home_screen.dart';
import 'package:dclix_app/screens/login_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';

const _stats = {
  'invoiceCount': 0,
  'dueAmount': 0,
  'myoffers': [
    {'code': 'SAMPLE01', 'name': 'Sample 60% Off for app users'},
  ],
};

Widget _wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UserSession.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
    );

void main() {
  late http.Client original;

  setUp(() {
    original = ApiService.client;
    SharedPreferences.setMockInitialValues({});
    final s = UserSession.instance;
    s.authData = {'id': 1, 'userType': 3, 'name': 'Alex Tan'};
    s.myInfo = {'name': 'Alex Tan'};
    s.homeStats = _stats;
    s.activeStudentName = null;
    ApiService.client = MockClient((req) async => http.Response(
        jsonEncode({'status': 200, 'data': req.url.path == '/Reports/HomePageStats' ? _stats : null}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'}));
  });

  tearDown(() {
    ApiService.client = original;
    UserSession.instance.authData = null;
    UserSession.instance.stopNotificationPolling();
  });

  testWidgets('Home has no Featured Offers carousel, even when offers come back', (tester) async {
    tester.view.physicalSize = const Size(2400, 7200);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(const HomeScreen()));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.textContaining('Featured Offer'), findsNothing);
    expect(find.text('Sample 60% Off for app users'), findsNothing);
  });

  testWidgets('sign-in has no "New to D-Clix? Contact your academy" line', (tester) async {
    await tester.pumpWidget(_wrap(const LoginScreen()));
    await tester.pump();

    expect(find.textContaining('New to D-Clix', findRichText: true), findsNothing);
    expect(find.textContaining('Contact your academy', findRichText: true), findsNothing);
  });

  test('the user guide no longer points at the removed sign-in line', () {
    final guide = [
      for (final s in kGuideSteps) ...[s.intro, s.note, ...s.tips, for (final d in s.details) d.text],
    ].join(' ');
    expect(guide, isNot(contains('bottom of this screen')));
  });
}
