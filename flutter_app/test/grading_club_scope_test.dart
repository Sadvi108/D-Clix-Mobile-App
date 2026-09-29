// Privacy (manual QA 2026-09-29): an instructor's Grading Schedule and Grade Completed listed
// other clubs' exams. /Reports/GradingSchedule returns every club's exam sessions to any
// instructor — a live probe for an instructor whose club has 4 exam centres got 764 rows across
// 80+ exam centres — and its rows carry no club field, only the exam centre name `ecName`.
//
// Every centre name here is invented.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:dclix_app/screens/instructor_reports/report_spec.dart';
import 'package:dclix_app/screens/instructor_reports/rn_reports.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/rn_api.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';

http.Response _ok(Object? data) => http.Response(jsonEncode({'status': 200, 'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// The instructor's own exam centres (`/Listing/DropdownListByType/2` is club-scoped).
const _ownCentres = [
  {'id': 1, 'value': 'Own Hall A', 'text': 'Own Hall A'},
  {'id': 2, 'value': 'Own School B', 'text': 'Own School B'},
];

final _today = DateTime.now().toIso8601String();

/// What /Reports/GradingSchedule hands any instructor: their exams and everyone else's.
List<Map<String, Object>> get _allClubsRows => [
      {'id': 10, 'resultId': 1, 'ecName': 'Own Hall A', 'examDate': _today, 'closingDate': _today, 'examTime': '9 AM'},
      {'id': 11, 'resultId': 2, 'ecName': 'Other Club Hall', 'examDate': _today, 'closingDate': _today, 'examTime': '10 AM'},
      {'id': 12, 'resultId': 3, 'ecName': ' own  school b ', 'examDate': _today, 'closingDate': _today, 'examTime': '11 AM'},
      {'id': 13, 'resultId': 4, 'ecName': 'Another Club Dojo', 'examDate': _today, 'closingDate': _today, 'examTime': '2 PM'},
    ];

void main() {
  late http.Client original;
  setUp(() => original = ApiService.client);
  tearDown(() => ApiService.client = original);

  void serve(http.Response Function() centres) {
    ApiService.client = MockClient((req) async => switch (req.url.path) {
          '/Reports/GradingSchedule' => _ok(_allClubsRows),
          '/Listing/DropdownListByType/2' => centres(),
          _ => _ok([]),
        });
  }

  test("keeps only exams at the instructor's own exam centres", () async {
    serve(() => _ok(_ownCentres));

    final rows = await RnApi.gradingSchedule({});

    expect(rows.map((r) => r['id']), [10, 12], reason: 'case and spacing differences still match');
  });

  test("fails closed when the club's exam-centre list comes back empty", () async {
    serve(() => http.Response(jsonEncode({'status': 200, 'meta': {'code': 200}}), 200));

    expect(await RnApi.gradingSchedule({}), isEmpty);
  });

  test("fails closed when the club's exam-centre list errors", () async {
    serve(() => http.Response('unavailable', 503));

    List<Map<String, dynamic>>? rows;
    try {
      rows = await RnApi.gradingSchedule({});
    } catch (_) {}
    expect(rows ?? const [], isEmpty, reason: "an error must never fall back to every club's rows");
  });

  test('no generic report spec fetches the grading schedule around the club scoping', () {
    // These called Api.reportsGradingSchedule raw. Unrouted today, but one route away from
    // showing every club's exams again.
    expect(kReportSpecs.keys.where((k) => k.startsWith('grading')), isEmpty);
  });

  testWidgets("Grade Completed lists the club's own exams, not another club's", (tester) async {
    tester.view.physicalSize = const Size(2400, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    serve(() => _ok(_ownCentres));

    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UserSession.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const RGradingScreen(title: 'Grade Completed')),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byWidgetPredicate((w) => w is Text && w.data == 'Search' && w.style?.color == Colors.white));
    await tester.pumpAndSettle();

    expect(find.text('Own Hall A'), findsOneWidget);
    expect(find.text('Other Club Hall'), findsNothing);
    expect(find.text('Another Club Dojo'), findsNothing);
  });
}
