// Every instructor centre picker reads one source. `/Listing/DropdownListByType/3` is the RN
// original, but routes in that family can answer with `data` omitted entirely (ARCHITECTURE.md
// records type 6 doing exactly that) — which left the Training Center picker empty on the
// Attendance, Receipt, Purchase Requests and Payment Slips reports, and left Student List and
// Training Schedule fanning out over nothing (manual QA 2026-09-24).
//
// `/Listing/TrainingCenters` answers the same question and is already trusted by
// student_list_fetch.dart and instructor_report_list_screen.dart, so it is the fallback.
import 'dart:convert';

import 'package:dclix_app/screens/instructor_reports/rn_reports.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/rn_api.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

http.Response ok(Object? data) =>
    http.Response(jsonEncode({'status': 200, 'data': data}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

/// The envelope shape that started this: HTTP 200, no `data` key at all.
http.Response noData() =>
    http.Response(jsonEncode({'status': 200, 'meta': {'code': 200}}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

Widget wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UserSession.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: child),
    );

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late List<String> paths;

  void serve(Map<String, http.Response Function()> routes) {
    paths = [];
    ApiService.client = MockClient((req) async {
      paths.add(req.url.path);
      for (final e in routes.entries) {
        if (req.url.path == e.key) return e.value();
      }
      return ok(<dynamic>[]);
    });
  }

  tearDown(() => ApiService.client = http.Client());

  test('uses DropdownListByType/3 when it answers, without a second request', () async {
    serve({
      '/Listing/DropdownListByType/3': () => ok([
            {'id': 7, 'text': 'Centre A'},
          ]),
    });

    final rows = await RnApi.trainingCentres();

    expect(rows, [
      {'id': 7, 'text': 'Centre A'}
    ]);
    expect(paths, ['/Listing/DropdownListByType/3']);
    expect(paths, isNot(contains('/Listing/TrainingCenters')));
  });

  test('falls back to /Listing/TrainingCenters on an empty list', () async {
    serve({
      '/Listing/DropdownListByType/3': () => ok(<dynamic>[]),
      '/Listing/TrainingCenters': () => ok([
            {'id': 3303, 'name': 'KCP'},
          ]),
    });

    expect(await RnApi.trainingCentres(), [
      {'id': 3303, 'text': 'KCP'}
    ]);
    expect(paths, ['/Listing/DropdownListByType/3', '/Listing/TrainingCenters']);
  });

  test('falls back when the envelope omits data entirely', () async {
    serve({
      '/Listing/DropdownListByType/3': noData,
      '/Listing/TrainingCenters': () => ok([
            {'id': 1, 'name': 'Only Centre'},
          ]),
    });

    expect(await RnApi.trainingCentres(), [
      {'id': 1, 'text': 'Only Centre'}
    ]);
  });

  test('normalises the key spellings the two routes disagree on', () async {
    serve({
      '/Listing/DropdownListByType/3': () => ok(<dynamic>[]),
      '/Listing/TrainingCenters': () => ok([
            {'centerId': 11, 'centerName': 'By centerName'},
            {'tCenterId': 12, 'tCenterName': 'By tCenterName'},
            {'name': 'No id at all'},
          ]),
    });

    // The row with no usable id is dropped — an option that can't be submitted is worse
    // than a missing one.
    expect(await RnApi.trainingCentres(), [
      {'id': 11, 'text': 'By centerName'},
      {'id': 12, 'text': 'By tCenterName'},
    ]);
  });

  testWidgets('the Attendance report centre picker fills from the fallback', (tester) async {
    serve({
      '/Listing/DropdownListByType/3': noData,
      '/Listing/TrainingCenters': () => ok([
            {'centerId': 3303, 'centerName': 'KCP'},
          ]),
    });

    await tester.pumpWidget(wrap(const RAttendanceScreen()));
    await settle(tester);

    await tester.tap(find.text('Select training center'));
    await settle(tester);

    expect(find.text('KCP'), findsWidgets);
  });
}
