// Manual QA 2026-09-29: two Approved bookings for Mon 28 Sep showed under Book a Class →
// My Bookings, while Schedule for that same day said "No classes scheduled".
//
// Schedule was built only from /Reports/StudentDetails — the member's recurring weekly
// timetable, matched by weekday. One-off bookings (/ClassBooking/GetBookings, dated by
// `trainingDate`) never reached it.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/screens/schedule_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/class_booking.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';

http.Response _ok(Object? data) => http.Response(jsonEncode({'status': 200, 'data': data}), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

Widget _wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UserSession.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A GetBookings row, in the shape Book a Class renders (live-probed, see
/// docs/superpowers/specs/2026-07-29-class-booking-contract.md).
Map<String, dynamic> _booking(DateTime day, String title, String centre, String status) => {
      'timeId': 1,
      'trainingDate': '${isoDate(day)}T00:00:00',
      'title': title,
      'centerName': centre,
      'status': status,
    };

void main() {
  late http.Client original;
  final today = DateTime.now();

  setUp(() {
    original = ApiService.client;
    SharedPreferences.setMockInitialValues({});
    final s = UserSession.instance;
    s.authData = {'id': 1, 'studentId': 1, 'userType': 3, 'name': 'Test Member'};
    s.myInfo = {'name': 'Test Member', 'studentId': 1};
    s.activeStudentId = null;
    s.activeStudentName = null;
  });

  tearDown(() {
    ApiService.client = original;
    UserSession.instance.stopNotificationPolling();
  });

  void serve({List<Object?> timetable = const [], List<Object?> bookings = const []}) {
    ApiService.client = MockClient((req) async => switch (req.url.path) {
          '/Reports/StudentDetails' => _ok(timetable),
          '/ClassBooking/GetBookings' => _ok(bookings),
          _ => _ok([]),
        });
  }

  testWidgets('an approved booking shows on its own date, not pending or other-date ones', (tester) async {
    serve(bookings: [
      _booking(today, '12:00 To 16:00 (Monday) - Normal training', 'Masjid Tengku Kelana Jaya', 'Approved'),
      _booking(today, '18:00 To 19:00 (Monday) - Normal training', 'Pending Centre', 'Pending'),
      _booking(today.add(const Duration(days: 3)), '09:00 To 10:00 - Normal training', 'Other Day Centre',
          'Approved'),
    ]);

    await tester.pumpWidget(_wrap(const ScheduleScreen()));
    await _settle(tester);

    expect(find.text('No classes scheduled'), findsNothing);
    expect(find.text('Masjid Tengku Kelana Jaya'), findsOneWidget);
    expect(find.text('12:00'), findsOneWidget);
    expect(find.text('to 16:00'), findsOneWidget);
    expect(find.text('Pending Centre'), findsNothing, reason: 'not on the schedule until approved');
    expect(find.text('Other Day Centre'), findsNothing, reason: 'booked for a different day');
  });

  testWidgets('booking your own regular class shows it once, not twice', (tester) async {
    // The timetable speaks 12-hour, booking titles 24-hour.
    serve(timetable: [
      {
        'studentName': 'Test Member',
        'dayOfWeek': DateFormat('EEEE').format(today),
        'tCenterName': 'Weekly Centre',
        'instructorName': 'Coach',
        'tTimeFrom': '8:00 PM',
        'tTimeTo': '9:00 PM',
      },
    ], bookings: [
      _booking(today, '20:00 To 21:00 - Normal training', 'Weekly Centre', 'Approved'),
    ]);

    await tester.pumpWidget(_wrap(const ScheduleScreen()));
    await _settle(tester);

    expect(find.text('Weekly Centre'), findsOneWidget);
  });

  testWidgets('a booked date gets the training dot in the day strip', (tester) async {
    serve(bookings: [
      _booking(today.add(const Duration(days: 2)), '12:00 To 13:00 - Normal training', 'Centre', 'Approved'),
    ]);

    await tester.pumpWidget(_wrap(const ScheduleScreen()));
    await _settle(tester);

    final dots = find.byWidgetPredicate((w) =>
        w is Container && w.constraints == const BoxConstraints.tightFor(width: 5, height: 5));
    expect(dots, findsOneWidget);
  });

  testWidgets('changing the selected student refetches that student schedule', (tester) async {
    final requestedStudents = <int>[];
    ApiService.client = MockClient((req) async {
      if (req.url.path == '/Reports/StudentDetails') {
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        final id = body['sourceKeyId'] as int;
        requestedStudents.add(id);
        return _ok([{
          'studentId': id,
          'studentName': id == 11 ? 'Child A' : 'Child B',
          'dayOfWeek': DateFormat('EEEE').format(today),
          'tCenterName': id == 11 ? 'Centre A' : 'Centre B',
          'tTimeFrom': '18:00',
          'tTimeTo': '19:00',
        }]);
      }
      return _ok([]);
    });
    final session = UserSession.instance;
    session.setActiveStudent(name: 'Child A', id: 11);
    addTearDown(() => session.setActiveStudent(name: null, id: null));
    await tester.pumpWidget(_wrap(const ScheduleScreen()));
    await _settle(tester);
    expect(find.text('Centre A'), findsOneWidget);
    session.setActiveStudent(name: 'Child B', id: 22);
    await _settle(tester);
    expect(find.text('Centre B'), findsOneWidget);
    expect(find.text('Centre A'), findsNothing);
    expect(requestedStudents, containsAllInOrder([11, 22]));
  });
}
