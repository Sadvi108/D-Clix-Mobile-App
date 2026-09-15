// Generates the user-guide screenshots.
//
//   flutter test tool/capture_guide_shots.dart --dart-define=CAPTURE=true
//
// It lives in tool/ and NOT in test/ on purpose: `flutter test` auto-discovers everything
// under test/, and this file installs an HttpOverrides and writes to assets/ — neither of
// which belongs in the normal suite.
//
// WHY A TEST AND NOT A DEVICE: a widget test renders the real screens deterministically at
// a fixed phone size, with no phone, no login and — critically — no real member's data. The
// Expo guide shipped screenshots containing a real name, phone number and member QR before
// that was caught. Every value here comes from tool/fake_api.dart, so a capture physically
// cannot contain anyone's record.
//
// The API is faked at the dart:io layer (see fake_api.dart) because ApiService calls
// package:http's top-level helpers and has no client to inject. Without that, every
// API-driven screen captured as an empty state.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:dclix_app/screens/home_screen.dart';
import 'package:dclix_app/screens/instructor_home_screen.dart';
import 'package:dclix_app/screens/instructor_reports_screen.dart';
import 'package:dclix_app/screens/instructor_collections_screen.dart';
import 'package:dclix_app/screens/profile_screen.dart';
import 'package:dclix_app/screens/payments_screen.dart';
import 'package:dclix_app/screens/tabs_shell.dart';
import 'package:dclix_app/screens/instructor_tabs_shell.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/screens/login_screen.dart';
import 'package:dclix_app/screens/more_screen.dart';
import 'package:dclix_app/screens/notification_settings_screen.dart';
import 'package:dclix_app/screens/notifications_screen.dart';
import 'package:dclix_app/screens/offers_screen.dart';
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
        theme: const bool.fromEnvironment('DARK_CAPTURE')
            ? AppTheme.dark()
            : AppTheme.light(),
        routerConfig: GoRouter(
          initialLocation: '/x',
          routes: [GoRoute(path: '/x', builder: (_, __) => child)],
        ),
      ),
    );

const _capture = bool.fromEnvironment('CAPTURE');

/// Fonts ship with the Flutter SDK. Without them every glyph renders as a filled box and
/// every Material icon as an empty square — fine for layout tests, useless for a picture.
String get _sdkCache {
  final configured = Platform.environment['FLUTTER_ROOT'];
  if (configured != null) return '$configured/bin/cache';
  var parent = File(Platform.resolvedExecutable).parent;
  while (parent.parent.path != parent.path) {
    if (Directory('${parent.path}/artifacts/material_fonts').existsSync())
      return parent.path;
    parent = parent.parent;
  }
  throw StateError('Set FLUTTER_ROOT to your Flutter SDK directory');
}

/// A common modern phone: 390 x 844 logical points at 3x.
const _phone = Size(1170, 2532);
const _phoneDpr = 3.0;

Future<void> _loadFont(String family, String path) async {
  final file = File(path);
  if (!file.existsSync()) throw StateError('font not found: $path');
  final loader = FontLoader(family)
    ..addFont(Future.value(file.readAsBytesSync().buffer.asByteData()));
  await loader.load();
}

/// Seeded from the same fixture the fake API serves, so a screen reading the session and a
/// screen reading the network show the same fictional member.
void _seedSession() {
  final s = UserSession.instance;
  s.authData = {
    'id': 1,
    'studentId': 1,
    'clubId': 1,
    'name': 'Alex Tan',
    'status': 'Active',
    'userType': 3
  };
  s.clubStats = [
    {'id': 128, 'text': 'Members', 'value': '1'},
    {'id': 6, 'text': 'Centres', 'value': '2'}
  ];
  s.myInfo = {
    'id': 1,
    'name': 'Alex Tan',
    'registrationNo': 'DCX-0001',
    'currentGrade': 'Green Belt',
    'tCenterName': 'Sample Training Centre',
    'eCenterName': 'Sample Exam Centre',
    'instructorName': 'Sensei Sample',
    'trainingTme': '8:00 PM - 9:30 PM',
    'handPhone': '000-0000000',
    'icNo': '000000-00-0000',
    'emailAddress': 'member@example.com',
    'clubName': 'D-CLIX Sample Academy',
    'attendancePercentage': '92',
  };
  s.studentAddtnlInfo = {
    'schoolname': 'Sample Secondary School',
    'dob': '2010-04-02T00:00:00',
    'bloodtype': 'O+',
    'healthstatus': 'Good',
  };
  // Seeded together with homeStats on purpose. Home reads the invoice list from the
  // session (UserSession.refresh fills it in the real app), and with only homeStats set the
  // screen said "RM170.00, 2 invoices outstanding" directly above "You're all paid up".
  // Worth knowing that state is reachable for real if one of the two fetches fails.
  s.outstandingList = [
    {
      'id': 5001,
      'invoiceNo': 'INV-2026-0091',
      'invoiceDescription': 'Monthly fee — September 2026',
      'period': 'Sep 2026',
      'dueAmount': 85.00,
      'invoiceDate': '2026-09-01T00:00:00',
      'studentId': 1,
      'studentName': 'Alex Tan',
    },
    {
      'id': 5002,
      'invoiceNo': 'INV-2026-0078',
      'invoiceDescription': 'Monthly fee — August 2026',
      'period': 'Aug 2026',
      'dueAmount': 85.00,
      'invoiceDate': '2026-08-01T00:00:00',
      'studentId': 1,
      'studentName': 'Alex Tan',
    },
  ];
  s.homeStats = {
    'invoiceCount': 2,
    'dueAmount': 170.00,
    'myoffers': [
      {
        'code': 'SAMPLE10',
        'title': 'Members save 10% on uniforms',
        'description': 'Show this screen at the counter. Sample offer.',
        'expiryDate': '2099-12-31T00:00:00',
      },
      {
        'code': 'SAMPLE20',
        'title': 'Bring a friend — free trial class',
        'description': 'Sample offer for illustration only.',
      },
    ],
  };
}

/// [inShell] reproduces what TabsShell does for a tab screen: provide the Scaffold. Those
/// screens return a bare Container because the shell wraps them, so capturing one on its
/// own renders Flutter's error widget instead.
Future<void> _shot(WidgetTester tester, String name, Widget screen,
    {bool inShell = false}) async {
  final previousShadows = debugDisableShadows;
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = previousShadows);
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = _phoneDpr;
  addTearDown(tester.view.reset);

  final key = GlobalKey();
  final content =
      inShell ? TabsShell(location: '/$name', child: screen) : screen;
  await tester.pumpWidget(_wrap(RepaintBoundary(key: key, child: content)));
  // runAsync so the client's future actually completes — flutter_test fakes the clock, and
  // under plain pump() the fixture arrived after the capture and every API-driven screen
  // came out as its empty state.
  //
  // NOT pumpAndSettle either: a screen showing a CircularProgressIndicator never settles.
  // Two rounds: some screens chain a second fetch off the first, and one pass of
  // runAsync + pump captured them mid-way through the chain.
  for (var round = 0; round < 3; round++) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 400));
    });
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  // toImage/toByteData do REAL work on the raster thread, which the faked test clock never
  // drives — outside runAsync the first capture wrote its PNG and then the run hung until
  // the harness gave up, taking every later capture with it.
  late final ByteData? bytes;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1.0);
    bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
  });

  // Refuse to ship a loading state OR an error screen. Both write a perfectly valid PNG
  // and pass silently — progress.png shipped as Flutter's red-and-yellow error widget and
  // was only caught by opening the file.
  // Only INDETERMINATE indicators mean "still loading". The attendance screen draws its
  // percentage as a determinate ring (value != null), which is finished UI — flagging that
  // rejected a perfectly good screenshot.
  final spinners = tester
      .widgetList<CircularProgressIndicator>(
          find.byType(CircularProgressIndicator))
      .where((w) => w.value == null);
  expect(spinners, isEmpty,
      reason:
          '$name captured while still loading; give it more time or stub what it awaits');
  expect(find.byType(ErrorWidget), findsNothing,
      reason:
          '$name captured as a Flutter error screen; it threw during build');

  const dark = bool.fromEnvironment('DARK_CAPTURE');
  const guide = {
    'login',
    'home',
    'attendance',
    'schedule',
    'book-class',
    'payments',
    'autopay',
    'notifications',
    'notification-settings',
    'student-details',
    'chat',
    'more'
  };
  final target = !dark && guide.contains(name)
      ? 'assets/guide'
      : '../docs/parity-captures/${dark ? 'dark' : 'light'}';
  final out = File('$target/$name.png');
  out.parent.createSync(recursive: true);
  out.writeAsBytesSync(bytes!.buffer.asUint8List());
  // ignore: avoid_print
  print('shot: ${out.path} (${out.lengthSync()} bytes)');

  await tester.pumpWidget(const SizedBox.shrink());
  debugDisableShadows = previousShadows;
}

void main() {
  const skipShots = !_capture;
  const skipReason = _capture
      ? null
      : 'pass --dart-define=CAPTURE=true to regenerate guide shots';

  setUpAll(() async {
    if (!_capture) return;
    await _loadFont('MaterialIcons',
        '$_sdkCache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    await _loadFont(
        'Roboto', '$_sdkCache/artifacts/material_fonts/Roboto-Regular.ttf');

    await _loadFont('Ionicons', 'assets/fonts/Ionicons.ttf');

    // Serve the fixture to every screen that fetches.
    ApiService.client = fakeApiClient();

    // ignore: invalid_use_of_visible_for_testing_member — this file IS run via
    // `flutter test`; it only lives outside test/ so the suite does not pick it up.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({
      // Auto Pay captured ON, so the shot shows the real settings rather than a bare
      // toggle.
      'dclix.autopay.v1':
          '{"enabled":true,"dayOfMonth":1,"monthsAhead":1,"payeeIds":[],"lastRemindedMs":null}',
    });

    // flutter_local_notifications has no platform side in a test; unanswered calls leave
    // the Auto Pay screen on its spinner.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dexterous.com/flutter/local_notifications'),
      // Types matter: the plugin casts these. `initialize` returning null instead of a
      // bool left NotificationService.init() awaiting forever and Auto Pay captured as a
      // spinner.
      (call) async => switch (call.method) {
        'initialize' => true,
        'getNotificationAppLaunchDetails' => <String, Object?>{
            'notificationLaunchedApp': false,
          },
        'pendingNotificationRequests' => <Map<String, Object?>>[],
        'getActiveNotifications' => <Map<String, Object?>>[],
        'areNotificationsEnabled' => true,
        'requestNotificationsPermission' => true,
        'requestPermissions' => true,
        'createNotificationChannel' => null,
        'cancel' => null,
        'zonedSchedule' => null,
        _ => null,
      },
    );

    _seedSession();
  });

  // UserSession is a singleton that starts a periodic notification poll; a live Timer keeps
  // the binding from finishing.
  tearDown(() => UserSession.instance.stopNotificationPolling());

  // One per guide page that has a screen worth showing.
  testWidgets('signin', (t) => _shot(t, 'login', const LoginScreen()),
      skip: skipShots);
  testWidgets(
      'home', (t) => _shot(t, 'home', const HomeScreen(), inShell: true),
      skip: skipShots);
  testWidgets(
      'checkin', (t) => _shot(t, 'attendance', const AttendanceScreen()),
      skip: skipShots);
  testWidgets('schedule',
      (t) => _shot(t, 'schedule', const ScheduleScreen(), inShell: true),
      skip: skipShots);
  testWidgets('booking', (t) => _shot(t, 'book-class', const BookClassScreen()),
      skip: skipShots);
  testWidgets('payments',
      (t) => _shot(t, 'payments', const PaymentsScreen(), inShell: true),
      skip: skipShots);
  testWidgets('autopay', (t) => _shot(t, 'autopay', const AutoPayScreen()),
      skip: skipShots);
  testWidgets('notifications',
      (t) => _shot(t, 'notifications', const NotificationsScreen()),
      skip: skipShots);
  testWidgets(
      'alerts',
      (t) =>
          _shot(t, 'notification-settings', const NotificationSettingsScreen()),
      skip: skipShots);
  testWidgets('profile',
      (t) => _shot(t, 'student-details', const StudentDetailsScreen()),
      skip: skipShots);
  testWidgets('chat', (t) => _shot(t, 'chat', const ChatScreen()),
      skip: skipShots);
  testWidgets('everything', (t) => _shot(t, 'more', const MoreScreen()),
      skip: skipShots);
  testWidgets('progress',
      (t) => _shot(t, 'progress', const ProgressScreen(), inShell: true),
      skip: skipShots);
  testWidgets('offers', (t) => _shot(t, 'offers', const OffersScreen()),
      skip: skipShots);
  testWidgets(
      'tournament', (t) => _shot(t, 'tournament', const TournamentScreen()),
      skip: skipShots);
  testWidgets('helpdesk', (t) => _shot(t, 'helpdesk', const HelpDeskScreen()),
      skip: skipShots);
  testWidgets(
      'purchases', (t) => _shot(t, 'purchases', const PurchasesScreen()),
      skip: skipShots);
  testWidgets('purchase-request',
      (t) => _shot(t, 'purchase-request', const PurchaseRequestScreen()),
      skip: skipShots);

  testWidgets('profile-card',
      (t) => _shot(t, 'profile-card', const ProfileScreen(), inShell: true),
      skip: skipShots);
  testWidgets(
      'instructor-home',
      (t) => _shot(
          t,
          'instructor-home',
          const InstructorTabsShell(
              location: '/instructor/home', child: InstructorHomeScreen())),
      skip: skipShots);

  testWidgets(
      'instructor-reports',
      (t) => _shot(
          t,
          'instructor-reports',
          const InstructorTabsShell(
              location: '/instructor/reports',
              child: InstructorReportsScreen())),
      skip: skipShots);
  testWidgets(
      'instructor-collections',
      (t) => _shot(
          t,
          'instructor-collections',
          const InstructorTabsShell(
              location: '/instructor/collections',
              child: InstructorCollectionsScreen())),
      skip: skipShots);

  test('the fixture is fictional', () {
    // A standing guard: if someone later seeds this from a live session these stop
    // matching, and a capture with real data fails rather than shipping.
    final s = UserSession.instance;
    if (s.myInfo == null) return;
    expect(s.myInfo!['name'], 'Alex Tan');
    expect('${s.myInfo!['handPhone']}', matches(RegExp(r'^0+-0+$')));
  }, skip: skipReason);
}
