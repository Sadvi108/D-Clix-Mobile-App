// The student's "Your info" card, back on Home as its main information card (2026-09-29).
// Every value comes from /Profile/MyInfo — whose student keys, as logged by the app, are
// registrationNo, eCenterName, tCenterName, currentGrade, lastGradingDate, nextGradingDate,
// tournamentName, tournamentDate, tournamentToDate, trainingTme, instructorName — except
// Student Code, which is the login's `code`.
//
// Every value here is invented.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/screens/home_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';

const _myInfo = {
  'id': 1,
  'name': 'Alex Tan',
  'registrationNo': 'DCX/SMP/2026/00001',
  'tCenterName': 'Sample Training Centre',
  'trainingTme': '10:00 To 11:20 (Sunday) - Normal training',
  'eCenterName': 'Sample Exam Hall',
  'instructorName': 'Sensei Sample',
  'currentGrade': 'Grade 6 (Green 1)',
  'lastGradingDate': '2026-08-08T00:00:00',
  'tournamentName': 'Sample Open 2026 @ Sample Arena',
  'tournamentDate': '2026-10-10T00:00:00',
  'tournamentToDate': '2026-10-10T00:00:00',
};

Widget _wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UserSession.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: SingleChildScrollView(child: child))),
    );

void main() {
  testWidgets('shows every Your info row from MyInfo', (tester) async {
    await tester.pumpWidget(_wrap(const YourInfoCard(info: _myInfo, studentCode: '00000001')));

    for (final (label, value) in const [
      ('Registration No', 'DCX/SMP/2026/00001'),
      ('Student Code', '00000001'),
      ('Training Centre', 'Sample Training Centre'),
      ('Training Time', '10:00 To 11:20 (Sunday) - Normal training'),
      ('Exam Center', 'Sample Exam Hall'),
      ('Instructor Name', 'Sensei Sample'),
      ('Current Grade', 'Grade 6 (Green 1)'),
      ('Last Grading Date', '08 Aug 2026'),
      ('Next Tournament', 'Sample Open 2026 @ Sample Arena'),
      ('Tournament Date', '10 Oct 2026'),
    ]) {
      expect(find.text(label), findsOneWidget, reason: label);
      expect(find.text(value), findsOneWidget, reason: '$label → $value');
    }
  });

  testWidgets('a multi-day tournament shows its date range', (tester) async {
    await tester.pumpWidget(_wrap(YourInfoCard(
        info: {..._myInfo, 'tournamentToDate': '2026-10-11T00:00:00'}, studentCode: '')));

    expect(find.text('10 Oct 2026 – 11 Oct 2026'), findsOneWidget);
  });

  testWidgets('a missing value shows a dash, never a blank', (tester) async {
    await tester.pumpWidget(_wrap(const YourInfoCard(info: {'name': 'Alex Tan'}, studentCode: '')));

    expect(find.text('Next Tournament'), findsOneWidget);
    expect(find.text('—'), findsNWidgets(10));
  });

  testWidgets("a guardian viewing another child is not shown this student's details", (tester) async {
    await tester.pumpWidget(_wrap(
        const YourInfoCard(info: _myInfo, studentCode: '00000001', activeStudentName: 'Mia Tan')));

    expect(find.text('DCX/SMP/2026/00001'), findsNothing);
    expect(find.text('Sample Open 2026 @ Sample Arena'), findsNothing);
    expect(find.textContaining('Mia Tan'), findsOneWidget);
  });

  group('on the Home screen', () {
    late http.Client original;

    setUp(() {
      original = ApiService.client;
      SharedPreferences.setMockInitialValues({});
      final s = UserSession.instance;
      s.authData = {'id': 1, 'userType': 3, 'name': 'Alex Tan', 'code': '00000001'};
      s.myInfo = null;
      s.homeStats = null;
      s.activeStudentId = null;
      s.activeStudentName = null;
      ApiService.client = MockClient((req) async => http.Response(
          jsonEncode({'status': 200, 'data': req.url.path == '/Profile/MyInfo' ? _myInfo : null}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'}));
    });

    tearDown(() {
      ApiService.client = original;
      UserSession.instance.stopNotificationPolling();
    });

    testWidgets('sits between Fees Due and Today\'s Class, wired to MyInfo and the login code', (tester) async {
      tester.view.physicalSize = const Size(2400, 7200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: UserSession.instance),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const Scaffold(body: HomeScreen())),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('DCX/SMP/2026/00001'), findsOneWidget);
      expect(find.text('00000001'), findsOneWidget);
      expect(find.text('Sample Open 2026 @ Sample Arena'), findsOneWidget);

      final fees = tester.getTopLeft(find.text('FEES DUE')).dy;
      final card = tester.getTopLeft(find.text('Your info')).dy;
      final today = tester.getTopLeft(find.text("Today's Class")).dy;
      expect(fees < card && card < today, isTrue, reason: 'FEES DUE $fees < Your info $card < Today\'s Class $today');
    });
  });
}
