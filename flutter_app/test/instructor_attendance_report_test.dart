import 'dart:convert';

import 'package:dclix_app/screens/instructor_reports/rn_reports.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';
import 'package:dclix_app/widgets/report_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

http.Response _ok(Object? data) => http.Response(
      jsonEncode({'status': 200, 'data': data}),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

Widget _wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UserSession.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Finder _select(String label) => find.byWidgetPredicate(
      (widget) => widget is SelectField && widget.label == label,
    );

void main() {
  late http.Client original;

  setUp(() => original = ApiService.client);
  tearDown(() => ApiService.client = original);

  testWidgets('online receipt search sends FPX', (tester) async {
    Map<String, dynamic>? body;
    ApiService.client = MockClient((request) async {
      if (request.url.path == '/Listing/DropdownListByType/3') {
        return _ok([
          {'id': 9, 'text': 'SK Jerantut'}
        ]);
      }
      if (request.url.path == '/Reports/Receipts') {
        body = jsonDecode(request.body) as Map<String, dynamic>;
      }
      return _ok(<dynamic>[]);
    });

    await tester.pumpWidget(_wrap(const RReceiptsScreen()));
    await _settle(tester);
    await tester.tap(_select('Payment Mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Online').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await _settle(tester);

    expect(body?['reportType'], 'FPX');
  });

  testWidgets('empty SK Jerantut roster falls back to attendance students',
      (tester) async {
    ApiService.client = MockClient((request) async {
      switch (request.url.path) {
        case '/Listing/DropdownListByType/3':
          return _ok([
            {'id': 3303, 'text': 'SK Jerantut'}
          ]);
        case '/Listing/TrainingTimeByTcId/3303':
          return _ok([
            {'id': 77, 'text': '18:00 To 19:30 (Monday)'}
          ]);
        case '/Listing/StudentListByTcId/3303':
          return _ok(<dynamic>[]);
        case '/Reports/Attendance':
          return _ok([
            {
              'studentId': 42,
              'name': 'Aisyah',
              'icNo': 'A42',
              'trainingCenter': 'SK Jerantut',
              'recordedTime': '2026-09-28T18:20:00',
              'attendanceType': 'Present',
            }
          ]);
      }
      return _ok(<dynamic>[]);
    });

    await tester.pumpWidget(_wrap(const RAttendanceScreen()));
    await _settle(tester);
    await tester.tap(_select('Training Center'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SK Jerantut').last);
    await _settle(tester);
    await tester.tap(_select('Student'));
    await tester.pumpAndSettle();

    expect(find.text('Aisyah'), findsOneWidget);
  });

  testWidgets('selected training time narrows returned attendance rows',
      (tester) async {
    ApiService.client = MockClient((request) async {
      switch (request.url.path) {
        case '/Listing/DropdownListByType/3':
          return _ok([
            {'id': 3303, 'text': 'SK Jerantut'}
          ]);
        case '/Listing/TrainingTimeByTcId/3303':
          return _ok([
            {'id': 10, 'text': '08:00 To 09:30 (Monday)'},
            {'id': 77, 'text': '18:00 To 19:30 (Monday)'},
          ]);
        case '/Listing/StudentListByTcId/3303':
          return _ok([
            {'id': 1, 'text': 'Morning Student', 'value': 'M1'},
            {'id': 2, 'text': 'Evening Student', 'value': 'E2'},
          ]);
        case '/Reports/Attendance':
          return _ok([
            {
              'name': 'Morning Student',
              'trainingCenter': 'SK Jerantut',
              'recordedTime': '2026-09-28T08:20:00',
              'attendanceType': 'Present',
            },
            {
              'name': 'Evening Student',
              'trainingCenter': 'SK Jerantut',
              'recordedTime': '2026-09-28T18:20:00',
              'attendanceType': 'Present',
            },
          ]);
      }
      return _ok(<dynamic>[]);
    });

    await tester.pumpWidget(_wrap(const RAttendanceScreen()));
    await _settle(tester);
    await tester.tap(_select('Training Center'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SK Jerantut').last);
    await _settle(tester);
    await tester.tap(_select('Training Time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('18:00 To 19:30 (Monday)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Search'));
    await _settle(tester);

    expect(find.text('Evening Student'), findsOneWidget);
    expect(find.text('Morning Student'), findsNothing);
  });
}
