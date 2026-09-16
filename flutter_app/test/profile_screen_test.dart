import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/screens/profile_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/theme_provider.dart';

http.Response _ok(Object? data) => http.Response(jsonEncode({'status': 200, 'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

Widget _wrap() => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<UserSession>.value(value: UserSession.instance),
      ],
      child: MaterialApp.router(
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => const Scaffold(body: ProfileScreen())),
        ]),
      ),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  late http.Client original;
  final copied = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    original = ApiService.client;
    copied.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add('${(call.arguments as Map)['text']}');
      return null;
    });
  });

  tearDown(() {
    ApiService.client = original;
    UserSession.instance.authData = null;
    UserSession.instance.myInfo = null;
    UserSession.instance.stopNotificationPolling();
  });

  testWidgets('student profile: member ID card, details, settings, copyable registration no', (tester) async {
    tester.view.physicalSize = const Size(1206, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    UserSession.instance.authData = {
      'id': 14,
      'name': 'Alex Tan',
      'userType': 3,
      'status': 'Active',
      'handPhone': '0123456789',
      'clubName': 'Sample Academy',
    };
    ApiService.client = MockClient((req) async => switch (req.url.path) {
          '/Profile/MyInfo' => _ok({
              'name': 'Alex Tan',
              'registrationNo': 'SAMPLE/2024/0001',
              'currentGrade': 'Grade 5 (Green 2)',
              'tCenterName': 'Sample Centre',
            }),
          '/Listing/MySiblings' => _ok([]),
          _ => http.Response('not found', 404),
        });

    await tester.pumpWidget(_wrap());
    await _settle(tester);

    expect(find.text('My Profile'), findsOneWidget);
    expect(find.text('MEMBER ID'), findsOneWidget);
    expect(find.text('Check In'), findsOneWidget);
    expect(find.text('MEMBER DETAILS'), findsOneWidget);
    expect(find.text('Switch student'), findsOneWidget);
    expect(find.text('Club overview'.toUpperCase()), findsNothing);
    expect(find.text('Log out'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Copy Registration no'));
    await tester.pump();
    expect(copied, ['SAMPLE/2024/0001']);
    expect(find.text('Registration no copied'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('instructor profile: staff ID, club overview, branches and branch switcher', (tester) async {
    tester.view.physicalSize = const Size(1206, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    UserSession.instance.authData = {
      'id': 2347,
      'name': 'Rick',
      'userType': 2,
      'status': 'Active',
      'clubName': 'Sample Taekwondo',
      'clubCode': 'SMP',
      'branchId': 1,
      'branchIds': [1, 2],
    };
    ApiService.client = MockClient((req) async => switch (req.url.path) {
          '/Profile/MyInfo' => _ok({'name': 'Rick'}),
          '/Profile/MyClubStats' => _ok([
              {'id': '120', 'text': 'Active Students', 'value': 1},
              {'id': '15', 'text': 'Training Times', 'value': 2},
            ]),
          '/Account/GetBranchesByClubCode/SMP' => _ok([
              {'id': 1, 'text': 'North Branch'},
              {'id': 2, 'text': 'South Branch'},
            ]),
          _ => http.Response('not found', 404),
        });

    await tester.pumpWidget(_wrap());
    await _settle(tester);

    expect(find.text('Instructor Profile'), findsOneWidget);
    expect(find.text('STAFF ID'), findsOneWidget);
    expect(find.text('CLUB OVERVIEW'), findsOneWidget);
    expect(find.text('120'), findsOneWidget);
    expect(find.text('Active Students'), findsOneWidget);
    expect(find.text('South Branch'), findsOneWidget);
    expect(find.text('Switch branch'), findsOneWidget);
    expect(find.text('North Branch'), findsWidgets, reason: 'current branch as chip and switcher value');
    expect(find.text('Switch student'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
