import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dclix_app/screens/home_screen.dart';
import 'package:dclix_app/screens/instructor_collections_screen.dart';
import 'package:dclix_app/screens/payment/bcpg_webview_screen.dart';
import 'package:dclix_app/screens/instructor_attendance_screen.dart';
import 'package:dclix_app/screens/login_screen.dart';
import 'package:dclix_app/screens/new_student_screen.dart';
import 'package:dclix_app/screens/payments_screen.dart';
import 'package:dclix_app/screens/payment/term_payment_screen.dart';
import 'package:dclix_app/screens/schedule_screen.dart';
import 'package:dclix_app/screens/tabs_shell.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/boost_payment.dart';
import 'package:dclix_app/services/manual_attendance.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';

http.Response ok(Object? data) =>
    http.Response(jsonEncode({'status': 200, 'data': data}), 200,
        headers: {'content-type': 'application/json; charset=utf-8'});

Widget wrap(Widget child, {bool dark = false}) => MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: UserSession.instance),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp(
            theme: dark ? AppTheme.dark() : AppTheme.light(),
            home: Scaffold(body: child)));

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late http.Client original;
  setUp(() {
    original = ApiService.client;
    SharedPreferences.setMockInitialValues({});
    final s = UserSession.instance;
    s.authData = {
      'id': 1,
      'studentId': 1,
      'userType': 3,
      'name': 'Test Member'
    };
    s.myInfo = {
      'name': 'Test Member',
      'studentId': 1,
      'currentGrade': 'Green Belt'
    };
    s.homeStats = {'invoiceCount': 0, 'dueAmount': 0};
    s.homeStatsError = null;
    s.outstandingList = [];
    s.activeStudentId = null;
    s.activeStudentName = null;
    s.loading = false;
    ApiService.client = MockClient((_) async => ok([]));
  });
  tearDown(() {
    ApiService.client = original;
    UserSession.instance.stopNotificationPolling();
  });

  test('HTTP 200 error envelopes fail without exposing SQL internals',
      () async {
    ApiService.client = MockClient((_) async => http.Response(
        jsonEncode({
          'status': 200,
          'meta': {'code': 400, 'error': 'Error converting nvarchar to int.'}
        }),
        200));
    await expectLater(
        ApiService.post('/Reports/Reimbursement', {}),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'code', 400)
            .having((e) => e.message, 'message', isNot(contains('nvarchar')))));
  });

  test('checkout returns only for a merchant URL', () {
    expect(
        BcpgWebViewScreen.isMerchantReturn(
            '${ApiService.boostBaseUrl}/Bcpg/Redirect?status=paid'),
        isTrue);
    expect(BcpgWebViewScreen.isMerchantReturn('dclix://bcpg-return'), isTrue);
    expect(
        BcpgWebViewScreen.isMerchantReturn(
            'https://unrelated.example/Bcpg/Redirect'),
        isFalse);
    expect(
        BcpgWebViewScreen.isMerchantReturn(
            'https://unrelated.example/?next=bcpg_redirect'),
        isFalse);
  });

  testWidgets('Update Collection recalculates each payment type once',
      (tester) async {
    final updates = <String>[];
    ApiService.client = MockClient((request) async {
      if (request.url.path.contains('/UpdateCollectionCount/'))
        updates.add(request.url.path.split('/').last);
      return ok({'cash': 2, 'fpx': 3, 'dbt': 4});
    });
    await tester.pumpWidget(wrap(const InstructorCollectionsScreen()));
    await settle(tester);
    await tester.tap(find.text('Update Collection'));
    await settle(tester);
    expect(updates, ['1', '2', '3']);
    expect(find.text('Counts refreshed from the server.'), findsOneWidget);
    expect(find.text('+1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'future fee quote without an invoice can reach payment confirmation',
      (tester) async {
    UserSession.instance.clearPaymentLock();
    ApiService.client = MockClient(
        (request) async => ok(request.url.path.contains('FetchTermPayments')
            ? [
                {
                  'studentId': 1,
                  'invoiceId': 0,
                  'dueAmount': 85,
                  'period': 'December',
                  'transactionType': 'Monthly'
                }
              ]
            : []));
    await tester.pumpWidget(wrap(const TermPaymentScreen()));
    await settle(tester);
    await tester.tap(find.text('Dec'));
    await settle(tester);
    await tester.ensureVisible(find.text('Pay Now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pay Now'));
    await settle(tester);
    expect(find.text('Confirm payment'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
  });

  testWidgets('payment account chips refetch invoices for the selected sibling',
      (tester) async {
    final queried = <int>[];
    ApiService.client = MockClient((request) async {
      if (request.url.path == '/Listing/MySiblings')
        return ok([
          {'id': 1, 'text': 'Test Member'},
          {'id': 2, 'text': 'Sibling'}
        ]);
      if (request.url.path == '/Outstanding/Fetch') {
        final id = (jsonDecode(request.body) as Map)['studentId'] as int;
        queried.add(id);
        return ok([
          {
            'id': id + 100,
            'studentId': id,
            'studentName': id == 2 ? 'Sibling' : 'Test Member',
            'invoiceDescription': 'Fee for account $id',
            'dueAmount': 85
          }
        ]);
      }
      return ok([]);
    });
    await tester.pumpWidget(wrap(const PaymentsScreen()));
    await settle(tester);
    expect(find.text('Fee for account 1'), findsOneWidget);
    await tester.tap(find.text('Sibling'));
    await settle(tester);
    expect(queried, [1, 2]);
    expect(find.text('Fee for account 2'), findsOneWidget);
    expect(find.text('Fee for account 1'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('weekly timetable is visible without any bookings',
      (tester) async {
    ApiService.client = MockClient(
        (request) async => ok(request.url.path == '/Reports/StudentDetails'
            ? [
                {
                  'studentId': 1,
                  'studentName': 'Test Member',
                  'dayOfWeek': DateFormat('EEEE').format(DateTime.now()),
                  'tCenterName': 'Weekly Centre',
                  'instructorName': 'Coach',
                  'tTimeFrom': '8 PM',
                  'tTimeTo': '9 PM'
                },
              ]
            : []));
    await tester.pumpWidget(wrap(const ScheduleScreen()));
    await settle(tester);
    expect(find.text('Weekly Centre'), findsOneWidget);
    expect(find.text('No classes scheduled'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed timetable request shows retry rather than Rest Day',
      (tester) async {
    ApiService.client = MockClient((request) async =>
        request.url.path == '/Reports/StudentDetails'
            ? http.Response('unavailable', 503)
            : ok([]));
    await tester.pumpWidget(wrap(const ScheduleScreen()));
    await settle(tester);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Rest Day'), findsNothing);
  });

  testWidgets(
      'instructor register stays hidden until the marking route is deployed',
      (tester) async {
    ManualAttendance.resetCache();
    ApiService.client = MockClient((request) async {
      if (request.url.path == '/swagger/v1/swagger.json') {
        return http.Response(
            jsonEncode({
              'paths': {'/Attendance/Add': {}}
            }),
            200);
      }
      if (request.url.path.contains('DropdownListByType')) {
        return ok([
          {'id': 1, 'text': 'Centre A'}
        ]);
      }
      if (request.url.path == '/Listing/StudentListByTcId/1') {
        return ok([
          {'id': 10, 'text': 'Alice', 'value': 'A10'}
        ]);
      }
      return ok([]);
    });
    await tester.pumpWidget(wrap(const InstructorAttendanceScreen()));
    await settle(tester);
    await tester.tap(find.text('Select centre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Centre A').last);
    await settle(tester);
    expect(find.text('Alice'), findsOneWidget);
    await tester.tap(find.text('Alice'));
    await settle(tester);
    expect(find.text('Select all'), findsNothing);
    expect(find.text('Select a training time first'), findsNothing);
    expect(find.textContaining(RegExp(r'^Mark \d+ present$')), findsNothing);
    expect(find.textContaining('needs a backend update'), findsOneWidget);
  });

  testWidgets('instructor ticks students, picks a time and saves the register',
      (tester) async {
    ManualAttendance.resetCache();
    Map<String, dynamic>? posted;
    ApiService.client = MockClient((request) async {
      final path = request.url.path;
      if (path == '/swagger/v1/swagger.json') {
        return http.Response(
            jsonEncode({
              'paths': {ManualAttendance.route: {}}
            }),
            200);
      }
      if (path.contains('DropdownListByType')) {
        return ok([
          {'id': 1, 'text': 'Centre A'}
        ]);
      }
      if (path == '/Listing/TrainingTimeByTcId/1') {
        return ok([
          {'id': 77, 'text': '8 PM'}
        ]);
      }
      if (path == '/Listing/StudentListByTcId/1') {
        return ok([
          {'id': 10, 'text': 'Alice', 'value': 'A10'},
          {'id': 11, 'text': 'Ben', 'value': 'B11'}
        ]);
      }
      if (path == ManualAttendance.route) {
        posted = jsonDecode(request.body) as Map<String, dynamic>;
        return ok([
          {'studentId': 10, 'status': 0, 'message': 'Marked present'}
        ]);
      }
      return ok([]);
    });
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const InstructorAttendanceScreen()));
    await settle(tester);
    await tester.tap(find.text('Select centre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Centre A').last);
    await settle(tester);

    await tester.tap(find.text('Alice'));
    await settle(tester);
    expect(find.text('Select a training time first'), findsOneWidget);
    await tester.tap(find.text('Select a training time first'));
    await settle(tester);
    expect(posted, isNull, reason: 'no class time, no save');

    await tester.tap(find.text('Select time'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('8 PM').last);
    await settle(tester);
    await tester.tap(find.text('Mark 1 present'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark present'));
    await tester.pumpAndSettle();
    await settle(tester);

    expect(posted!['tCenterId'], 1);
    expect(posted!['tTimeId'], 77);
    expect(posted!['entries'], [
      {'studentId': 10, 'attendanceTypeId': ManualAttendance.presentTypeId}
    ]);
    expect(find.text('Attendance saved'), findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('Marked present'), findsOneWidget);
    expect(find.textContaining('Mark 1 present'), findsNothing,
        reason: 'saved students are unticked');
  });

  testWidgets('instructor centre switch clears the old roster on failure',
      (tester) async {
    final writes = <String>[];
    ApiService.client = MockClient((request) async {
      if (request.method != 'GET') writes.add(request.url.path);
      if (request.url.path.contains('DropdownListByType'))
        return ok([
          {'id': 1, 'text': 'Centre A'},
          {'id': 2, 'text': 'Centre B'}
        ]);
      if (request.url.path == '/Listing/StudentListByTcId/1')
        return ok([
          {'id': 10, 'text': 'Alice', 'value': 'A10'}
        ]);
      if (request.url.path == '/Listing/StudentListByTcId/2')
        return http.Response('down', 500);
      return ok([]);
    });
    await tester.pumpWidget(wrap(const InstructorAttendanceScreen()));
    await settle(tester);
    // The centre picker is a bottom-sheet list (reportkit SelectField).
    await tester.tap(find.text('Select centre'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Centre A').last);
    await settle(tester);
    expect(find.text('Alice'), findsOneWidget);
    expect(find.text('Show Centre QR'), findsOneWidget);
    expect(find.text('Mark Present'), findsNothing);
    await tester.tap(find.text('Centre A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Centre B').last);
    await settle(tester);
    expect(find.text('Alice'), findsNothing);
    expect(find.text('Try again'), findsOneWidget);
    expect(writes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'new student endpoint unavailable is explicit, not an enrolled student list',
      (tester) async {
    ApiService.client =
        MockClient((_) async => http.Response('Not Found', 404));
    await tester.pumpWidget(wrap(const NewStudentScreen()));
    await settle(tester);
    expect(find.text('Awaiting backend'), findsOneWidget);
    expect(find.text('All caught up'), findsNothing);
  });

  testWidgets('payment history deep link opens History and switches to advance',
      (tester) async {
    await tester.pumpWidget(wrap(const PaymentsScreen(initialTab: 'history')));
    await settle(tester);
    expect(find.text('No receipts found.'), findsOneWidget);
    expect(find.text('Auto Pay'), findsNothing);
    await tester.tap(find.text('Advance Payment'));
    await settle(tester);
    expect(find.text('Select Month(s) to PAY'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('failed home stats are never displayed as zero dues',
      (tester) async {
    UserSession.instance.homeStats = null;
    UserSession.instance.homeStatsError = 'unavailable';
    ApiService.client = MockClient((request) async =>
        request.url.path == '/Reports/HomePageStats'
            ? http.Response('unavailable', 503)
            : ok([]));
    final router = GoRouter(routes: [
      GoRoute(
          path: '/',
          builder: (_, __) =>
              const TabsShell(location: '/home', child: HomeScreen()))
    ]);
    await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider.value(value: UserSession.instance)],
        child:
            MaterialApp.router(theme: AppTheme.light(), routerConfig: router)));
    await settle(tester);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('RM 0.00'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    router.dispose();
  });

  testWidgets('branch search keeps the typed query across sheet rebuilds',
      (tester) async {
    ApiService.client = MockClient((_) async => ok([
          {'id': 1, 'text': 'North'},
          {'id': 2, 'text': 'South'}
        ]));
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(const LoginScreen()));
    await settle(tester);
    await tester.tap(find.text('Instructor'));
    await settle(tester);
    await tester.enterText(find.byType(TextField).first, 'CLUB');
    await settle(tester);
    await tester.ensureVisible(find.text('Select branch'));
    await tester.tap(find.text('Select branch'));
    await settle(tester);
    // The sheet lists the branches for the club code just typed…
    expect(find.text('North'), findsOneWidget);
    expect(find.text('South'), findsOneWidget);
    await tester.tap(find.text('South'));
    await settle(tester);
    // …and the pick lands in the field, with the typed club code untouched.
    expect(find.text('South'), findsOneWidget);
    expect(find.text('North'), findsNothing);
    expect(find.text('CLUB'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('partial multi-student reconciliation is unknown', () async {
    final result = await BoostPayment.confirm(
        invoiceIds: [1, 2],
        studentIds: [10, 11],
        attempts: 0,
        fetchOutstandingIds: (id) async {
          if (id == 11) throw Exception('offline');
          return [];
        });
    expect(result.outcome, PaymentOutcome.unknown);
  });

  test(
      'bank slip multipart preserves every InvoiceIds field and actual file bytes',
      () async {
    late String body;
    ApiService.client = MockClient((request) async {
      body = request.body;
      return ok(null);
    });
    await ApiService.postMultipart(
        '/Outstanding/PayInvoices?PayTermPayments=false&PurchaseItems=false', {
      'PaymentMethod': '1'
    },
        repeatedFields: {
          'InvoiceIds': ['123', '456']
        },
        uploads: [
          (name: 'slip.jpg', bytes: Uint8List.fromList([65, 66, 67]))
        ]);
    expect(RegExp('name="InvoiceIds"').allMatches(body).length, 2);
    expect(body, contains('123'));
    expect(body, contains('456'));
    expect(body, contains('filename="slip.jpg"'));
    expect(body, contains('ABC'));
  });

  test('HTTP server errors never expose SQL or HTML response bodies', () async {
    ApiService.client = MockClient((_) async =>
        http.Response('<html>SqlException private table secret</html>', 500));
    try {
      await ApiService.get('/Profile/MyInfo');
      fail('expected API failure');
    } on ApiException catch (e) {
      expect(e.statusCode, 500);
      expect(e.message, isNot(contains('secret')));
    }
  });
}
