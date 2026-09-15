// Which screens render cleanly under the capture harness?
//
//   flutter test tool/render_check.dart
//
// Renders every screen the guide wants a picture of, with the same fake API and fixture the
// capture uses, and reports OK or the exception. No images are written — this also tests
// whether the image capture is what makes the capture run hang.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/screens/attendance_screen.dart';
import 'package:dclix_app/screens/autopay_screen.dart';
import 'package:dclix_app/screens/book_class_screen.dart';
import 'package:dclix_app/screens/chat_screen.dart';
import 'package:dclix_app/screens/tournament_screen.dart';
import 'package:dclix_app/screens/helpdesk_screen.dart';
import 'package:dclix_app/screens/login_screen.dart';
import 'package:dclix_app/screens/more_screen.dart';
import 'package:dclix_app/screens/notification_settings_screen.dart';
import 'package:dclix_app/screens/notifications_screen.dart';
import 'package:dclix_app/screens/offers_screen.dart';
import 'package:dclix_app/screens/outstanding_invoices_screen.dart';
import 'package:dclix_app/screens/progress_screen.dart';
import 'package:dclix_app/screens/purchase_request_screen.dart';
import 'package:dclix_app/screens/purchases_screen.dart';
import 'package:dclix_app/screens/schedule_screen.dart';
import 'package:dclix_app/screens/student_details_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/theme_provider.dart';

import 'fake_api.dart';

/// The same providers main.dart installs. LoginScreen watches ThemeProvider and threw
/// "Could not find the correct Provider<ThemeProvider>" without it.
///
/// A plain ThemeData on purpose: AppTheme.light() constructs GoogleFonts, which fires an
/// async font download the test HttpClient refuses, and the placeholder font comes back.
/// context.appColors falls back to AppColors.light, so the palette is still the real one.
Widget _wrap(Widget child) => MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<UserSession>.value(value: UserSession.instance),
      ],
      // MaterialApp.router, not MaterialApp: ProgressScreen reads GoRouter in build and
      // threw "No GoRouter found in context", which captured as Flutter's error widget.
      child: MaterialApp.router(
        theme: ThemeData(fontFamily: 'Roboto'),
        routerConfig: GoRouter(
          initialLocation: '/x',
          routes: [GoRoute(path: '/x', builder: (_, __) => child)],
        ),
      ),
    );

final _report = <String>[];

Future<void> check(WidgetTester tester, String name, Widget screen) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  try {
    // runAsync, because flutter_test fakes the clock: a plain pump() never lets the
    // client's future complete, so the fixture arrived after the frame and every
    // API-driven screen rendered its empty state.
    await tester.runAsync(() async {
      await tester.pumpWidget(_wrap(screen));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    for (var i = 0; i < 3; i++) {
      await tester.pump(const Duration(milliseconds: 120));
    }
    final e = tester.takeException();
    if (e == null) {
      // Any text at all means it drew something rather than an empty frame.
      final texts = tester.widgetList<Text>(find.byType(Text)).length;
      _report.add('OK    $name  ($texts text widgets)');
    } else {
      final msg = e.toString().split('\n').first;
      _report.add('THROW $name  ${msg.length > 100 ? msg.substring(0, 100) : msg}');
    }
  } catch (e) {
    final msg = e.toString().split('\n').first;
    _report.add('FAIL  $name  ${msg.length > 100 ? msg.substring(0, 100) : msg}');
  }
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  setUpAll(() {
    ApiService.client = fakeApiClient();
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      'dclix.autopay.v1':
          '{"enabled":true,"dayOfMonth":1,"monthsAhead":1,"payeeIds":[],"lastRemindedMs":null}',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      (call) async => switch (call.method) {
        'pendingNotificationRequests' => <Map<String, Object?>>[],
        'areNotificationsEnabled' => true,
        _ => null,
      },
    );
    UserSession.instance.myInfo = {
      'id': 1,
      'name': 'Alex Tan',
      'registrationNo': 'DCX-0001',
      'currentGrade': 'Green Belt',
      'tCenterName': 'Sample Training Centre',
      'handPhone': '000-0000000',
      'clubName': 'D-CLIX Sample Academy',
    };
    UserSession.instance.homeStats = {
      'myoffers': [
        {'code': 'SAMPLE10', 'title': 'Members save 10% on uniforms'},
      ],
    };
  });

  tearDown(() => UserSession.instance.stopNotificationPolling());
  tearDownAll(() {
    // ignore: avoid_print
    print('\n=== render check ===\n${_report.join('\n')}\n');
  });

  testWidgets('login', (t) => check(t, 'login', const LoginScreen()));
  testWidgets('attendance', (t) => check(t, 'attendance', const AttendanceScreen()));
  testWidgets('schedule', (t) => check(t, 'schedule', const ScheduleScreen()));
  testWidgets('book-class', (t) => check(t, 'book-class', const BookClassScreen()));
  testWidgets('invoices', (t) => check(t, 'invoices', const OutstandingInvoicesScreen()));
  testWidgets('autopay', (t) => check(t, 'autopay', const AutoPayScreen()));
  testWidgets('notifications', (t) => check(t, 'notifications', const NotificationsScreen()));
  testWidgets('alerts', (t) => check(t, 'alerts', const NotificationSettingsScreen()));
  testWidgets('details', (t) => check(t, 'details', const StudentDetailsScreen()));
  testWidgets('chat', (t) => check(t, 'chat', const ChatScreen()));
  testWidgets('more', (t) => check(t, 'more', const MoreScreen()));
  testWidgets('progress', (t) => check(t, 'progress', const ProgressScreen()));
  testWidgets('offers', (t) => check(t, 'offers', const OffersScreen()));
  testWidgets('tournament', (t) => check(t, 'tournament', const TournamentScreen()));
  testWidgets('helpdesk', (t) => check(t, 'helpdesk', const HelpDeskScreen()));
  testWidgets('purchases', (t) => check(t, 'purchases', const PurchasesScreen()));
  testWidgets('purchase-req',
      (t) => check(t, 'purchase-req', const PurchaseRequestScreen()));
}
