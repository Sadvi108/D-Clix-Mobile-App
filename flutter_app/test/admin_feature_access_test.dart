// Club-master feature switches arrive in /Account/Authenticate. A disabled
// feature must disappear from navigation, reject deep links, and avoid calling
// the APIs behind a screen the user is not allowed to open.
import 'package:dclix_app/router/app_router.dart';
import 'package:dclix_app/screens/book_class_screen.dart';
import 'package:dclix_app/screens/instructor_collections_screen.dart';
import 'package:dclix_app/screens/instructor_home_screen.dart';
import 'package:dclix_app/screens/more_screen.dart';
import 'package:dclix_app/screens/outstanding_invoices_screen.dart';
import 'package:dclix_app/screens/payments_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/widgets/club_tab_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final session = UserSession.instance;
  late http.Client originalClient;

  setUp(() {
    originalClient = ApiService.client;
    session.authData = {
      'id': 42,
      'studentId': 42,
      'userType': 3,
      'name': 'Test Member',
    };
  });

  tearDown(() {
    ApiService.client = originalClient;
    session.authData = null;
  });

  Widget wrap(Widget child, {bool provideSession = false}) {
    final app = MaterialApp(theme: AppTheme.light(), home: child);
    return provideSession
        ? ChangeNotifierProvider<UserSession>.value(value: session, child: app)
        : app;
  }

  test('authentication flags map to the club-master feature switches', () {
    session.authData = {
      'isClassBookingEnabled': false,
      'permissions': {'2': false, '3': false, '4': true},
    };

    expect(session.allowClassBooking, isFalse);
    expect(session.allowViewInvoices, isFalse);
    expect(session.allowViewCollections, isFalse);
    expect(session.allowUpdateCollection, isTrue,
        reason:
            'viewing and recalculating collections are separate admin permissions');

    session.authData = {
      'isClassBookingEnabled': true,
      'permissions': {'3': true, '4': false},
    };
    expect(session.allowClassBooking, isTrue);
    expect(session.allowViewCollections, isTrue);
    expect(session.allowUpdateCollection, isFalse);
  });

  test('deep links are rejected when their API feature is disabled', () {
    session.authData = {
      'isClassBookingEnabled': false,
      'permissions': {'3': false},
    };

    expect(permissionRedirect('/book-class'), '/schedule');
    expect(permissionRedirect('/instructor/collections'), '/instructor/home');
    expect(permissionRedirect('/instructor/collections/1'), '/instructor/home');
  });

  testWidgets('disabled Book a Class makes no booking API requests',
      (tester) async {
    session.authData = {
      'id': 42,
      'studentId': 42,
      'userType': 3,
      'name': 'Test Member',
      'isClassBookingEnabled': false,
    };
    final requests = <Uri>[];
    ApiService.client = MockClient((request) async {
      requests.add(request.url);
      return http.Response('{"status":200,"data":[]}', 200);
    });

    await tester.pumpWidget(wrap(const BookClassScreen()));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Class booking is switched off'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets('disabled Collections makes no collection API requests',
      (tester) async {
    session.authData = {
      'id': 7,
      'userType': 0,
      'permissions': {'3': false, '4': true},
    };
    final requests = <Uri>[];
    ApiService.client = MockClient((request) async {
      requests.add(request.url);
      return http.Response('{"status":200,"data":{}}', 200);
    });

    await tester.pumpWidget(wrap(const InstructorCollectionsScreen()));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Collections are not available'), findsOneWidget);
    expect(requests, isEmpty);
  });

  testWidgets(
      'disabled outstanding dues stays hidden and makes no invoice request',
      (tester) async {
    session.authData = {
      'id': 7,
      'userType': 0,
      'name': 'Test Instructor',
      'permissions': {'2': false},
    };
    final requests = <Uri>[];
    ApiService.client = MockClient((request) async {
      requests.add(request.url);
      return http.Response('{"status":200,"data":[]}', 200);
    });

    await tester
        .pumpWidget(wrap(const InstructorHomeScreen(), provideSession: true));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('OUTSTANDING DUES'), findsNothing);
    expect(find.text('Missing Invoice'), findsNothing);
    expect(requests.where((u) => u.path == '/Outstanding/Fetch'), isEmpty);
  });

  testWidgets('disabled features disappear from their navigation entry points',
      (tester) async {
    session.authData = {
      'id': 7,
      'userType': 0,
      'isClassBookingEnabled': false,
      'permissions': {'3': false},
    };

    await tester.pumpWidget(wrap(const MoreScreen()));
    expect(find.text('Book a Class'), findsNothing);

    await tester.pumpWidget(wrap(
        const Scaffold(
          bottomNavigationBar:
              ClubTabBar(location: '/instructor/home', instructor: true),
        ),
        provideSession: true));
    expect(find.text('Collections'), findsNothing);
    expect(find.text('Check-In'), findsOneWidget);
  });

  test('isAutoPayEnabled maps to allowAutoPay, and an absent flag stays allowed',
      () {
    session.authData = {'isAutoPayEnabled': true};
    expect(session.allowAutoPay, isTrue);

    session.authData = {};
    expect(session.allowAutoPay, isTrue,
        reason: 'the backend does not send every switch to every account');

    session.authData = {'isAutoPayEnabled': false};
    expect(session.allowAutoPay, isFalse);
  });

  test('a disabled Auto Pay sends /autopay to Pay Your Dues', () {
    expect(permissionRedirect('/autopay'), isNull,
        reason: 'no isAutoPayEnabled in the login payload: allowed');

    session.authData = {'isAutoPayEnabled': false};
    expect(permissionRedirect('/autopay'), '/invoices');
  });

  testWidgets('a disabled /autopay pushed from outside the tab bar lands cleanly',
      (tester) async {
    // A notification tap pushes /autopay from wherever the member is. Redirecting that push
    // onto a tab-bar route (/payments) from a page outside the shell (/chat) makes go_router
    // clone the ShellRoute: a duplicate GlobalKey in debug, a blank page in release. /invoices
    // lives outside the shell, like /autopay itself, so the push stays a plain push.
    tester.view.physicalSize = const Size(2400, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    session.authData = {...session.authData!, 'isAutoPayEnabled': false};
    ApiService.client =
        MockClient((_) async => http.Response('{"status":200,"data":[]}', 200));
    final router = GoRouter(
      initialLocation: '/chat',
      routes: appRouter.configuration.routes,
      redirect: (_, state) => permissionRedirect(state.matchedLocation),
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(ChangeNotifierProvider<UserSession>.value(
      value: session,
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    router.push('/autopay');
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(tester.takeException(), isNull);
    expect(find.byType(OutstandingInvoicesScreen), findsOneWidget);
    session.stopNotificationPolling();
  });

  for (final (flag, shown) in [(false, false), (null, true)]) {
    testWidgets(
        'Payments and All Features ${shown ? 'show' : 'hide'} Auto Pay '
        'when isAutoPayEnabled is ${flag ?? 'absent'}', (tester) async {
      // Tall enough that All Features builds every section (its list is lazy).
      tester.view.physicalSize = const Size(2400, 7200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);
      session.authData = {
        ...session.authData!,
        if (flag != null) 'isAutoPayEnabled': flag,
      };
      ApiService.client = MockClient(
          (_) async => http.Response('{"status":200,"data":[]}', 200));
      final autoPay = shown ? findsOneWidget : findsNothing;

      await tester.pumpWidget(
          wrap(const Scaffold(body: PaymentsScreen()), provideSession: true));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Auto Pay'), autoPay);

      await tester.pumpWidget(wrap(const MoreScreen()));
      expect(find.text('Auto Pay'), autoPay);
    });
  }
}
