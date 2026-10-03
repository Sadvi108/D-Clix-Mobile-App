import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'package:dclix_app/screens/manual_attendance_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/manual_attendance.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';

http.Response _ok(Object? data) => http.Response(
    jsonEncode({
      'status': 200,
      'meta': {'code': 200},
      'data': data
    }),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'});

String _day(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}T00:00:00';

void main() {
  late http.Client original;
  setUp(() => original = ApiService.client);
  tearDown(() => ApiService.client = original);

  group('ManualAttendance', () {
    test('reads centres, class times and the class list from the UAT host', () async {
      final seen = <Uri>[];
      ApiService.client = MockClient((req) async {
        seen.add(req.url);
        return switch (req.url.path) {
          '/Attendance/Centres' => _ok([
              {'id': 3, 'value': '3', 'text': 'Centre A'}
            ]),
          '/Attendance/TrainingTimes' => _ok([
              {'id': 77, 'value': '77', 'text': '8 PM'}
            ]),
          '/Attendance/People' => _ok([
              {'id': 10, 'name': ' Alice ', 'alreadyMarked': false},
              {'id': 11, 'name': 'Ben', 'alreadyMarked': true},
            ]),
          _ => _ok(null),
        };
      });
      final date = DateTime(2026, 10, 3, 18, 30);

      expect((await ManualAttendance.centres()).single['text'], 'Centre A');
      expect((await ManualAttendance.trainingTimes(3, date)).single['id'], 77);
      final people = await ManualAttendance.people(type: ManualAttendance.student, centreId: 3, timeId: 77, date: date);

      expect(people, [(id: 10, name: 'Alice', alreadyMarked: false), (id: 11, name: 'Ben', alreadyMarked: true)]);
      expect(seen.map((u) => u.host).toSet(), {Uri.parse(ApiService.boostBaseUrl).host},
          reason: 'these routes are deployed on UAT only');
      expect(seen[1].queryParameters, {'centreId': '3', 'date': '2026-10-03T00:00:00'});
      expect(
          seen[2].queryParameters, {'type': 'Student', 'centreId': '3', 'timeId': '77', 'date': '2026-10-03T00:00:00'});
    });

    test('posts the class and the people, and reads back who was added', () async {
      Map<String, dynamic>? sent;
      ApiService.client = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/Attendance/ManualAdd');
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return _ok({
          'added': 1,
          'alreadyMarkedIds': [12]
        });
      });
      final result = await ManualAttendance.add(
          type: ManualAttendance.instructor, centreId: 3, timeId: 77, date: DateTime(2026, 10, 3), personIds: [11, 12]);
      expect(sent, {
        'type': 'Instructor',
        'centreId': 3,
        'timeId': 77,
        'date': '2026-10-03T00:00:00',
        'personIds': [11, 12],
      });
      expect(result.added, 1);
      expect(result.alreadyMarkedIds, [12]);
    });

    test('a server refusal is thrown, never read as saved', () async {
      ApiService.client = MockClient((_) async => http.Response(
          jsonEncode({
            'status': 400,
            'meta': {'code': 400, 'error': 'Date cannot be in the future'}
          }),
          200));
      await expectLater(
          ManualAttendance.add(
              type: ManualAttendance.student, centreId: 3, timeId: 77, date: DateTime(2026, 10, 3), personIds: [10]),
          throwsA(isA<ApiException>().having((e) => e.message, 'message', contains('future'))));
    });
  });

  group('ManualAttendanceScreen', () {
    late List<Uri> gets;
    Map<String, dynamic>? posted;
    var marked = <int>{11};

    setUp(() {
      gets = [];
      posted = null;
      marked = {11};
      ApiService.client = MockClient((req) async {
        if (req.method == 'POST') {
          posted = jsonDecode(req.body) as Map<String, dynamic>;
          final ids = (posted!['personIds'] as List).cast<int>();
          marked.addAll(ids);
          return _ok({'added': ids.length, 'alreadyMarkedIds': <int>[]});
        }
        gets.add(req.url);
        return switch (req.url.path) {
          '/Attendance/Centres' => _ok([
              {'id': 3, 'value': '3', 'text': 'Centre A'}
            ]),
          '/Attendance/TrainingTimes' => _ok([
              {'id': 77, 'value': '77', 'text': '8 PM'}
            ]),
          '/Attendance/People' => req.url.queryParameters['type'] == 'Instructor'
              ? _ok([
                  {'id': 90, 'name': 'Coach Lee', 'alreadyMarked': false}
                ])
              : _ok([
                  for (final (id, name) in [(10, 'Alice'), (11, 'Ben'), (12, 'Chan')])
                    {'id': id, 'name': name, 'alreadyMarked': marked.contains(id)}
                ]),
          _ => _ok(null),
        };
      });
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: UserSession.instance),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const ManualAttendanceScreen()),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select centre'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Centre A').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('8 PM').last);
      await tester.pumpAndSettle();
    }

    testWidgets('marks the ticked students present for the chosen class and date', (tester) async {
      await open(tester);
      final today = DateTime.now();
      expect(gets.firstWhere((u) => u.path == '/Attendance/TrainingTimes').queryParameters,
          {'centreId': '3', 'date': _day(today)});

      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('Already marked'), findsOneWidget, reason: 'Ben was marked for this class already');
      await tester.tap(find.text('Ben'));
      await tester.pump();
      expect(find.textContaining('Save attendance'), findsNothing, reason: 'an already-marked person cannot be ticked');

      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Save attendance (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Mark 1 student present?'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(posted, {
        'type': 'Student',
        'centreId': 3,
        'timeId': 77,
        'date': _day(today),
        'personIds': [10],
      });
      expect(find.text('Attendance saved'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Already marked'), findsNWidgets(2), reason: 'the list is re-read after saving');
      expect(find.textContaining('Save attendance'), findsNothing);
    });

    testWidgets('select all ticks only the people not yet marked', (tester) async {
      await open(tester);
      await tester.tap(find.text('Select all'));
      await tester.pump();
      await tester.tap(find.text('Save attendance (2)'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(posted!['personIds'], [10, 12]);
    });

    testWidgets('switching to instructors loads the instructor list and drops the ticks', (tester) async {
      await open(tester);
      await tester.tap(find.text('Alice'));
      await tester.pump();
      await tester.tap(find.text('Instructor'));
      await tester.pumpAndSettle();
      expect(find.text('Coach Lee'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
      expect(find.textContaining('Save attendance'), findsNothing);
    });

    testWidgets('search narrows the class list to the student being covered', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'cha');
      await tester.pump();
      expect(find.text('Chan'), findsOneWidget);
      expect(find.text('Alice'), findsNothing);
    });
  });
}
