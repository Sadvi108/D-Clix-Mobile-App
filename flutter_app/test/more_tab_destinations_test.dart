// Manual QA 2026-09-29: from All Features, every tile that lands on a bottom-tab screen —
// Training, Today's Classes, Timetable, My Trainer, Fees Due, Payment History, Advance
// Payment, Progress Report, Profile — opened a blank body under the tab bar, no error.
//
// /more sat outside the student ShellRoute. Pushing a shell route from a page outside the
// shell makes go_router clone a second ShellRouteMatch (go_router 14, match.dart
// `_createNewMatchUntilIncompatible`), and both copies build their nested Navigator with the
// ShellRoute's single navigatorKey — a duplicate GlobalKey. Debug builds throw; release
// builds leave one of the two navigators empty, which is the blank screen.
//
// These drive the app's REAL route table. The earlier back-navigation tests used flat toy
// routers with no ShellRoute at all, which is how this shipped past them.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/router/app_router.dart';
import 'package:dclix_app/screens/more_screen.dart';
import 'package:dclix_app/screens/payments_screen.dart';
import 'package:dclix_app/screens/profile_screen.dart';
import 'package:dclix_app/screens/progress_screen.dart';
import 'package:dclix_app/screens/schedule_screen.dart';
import 'package:dclix_app/screens/training_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/ion.dart';
import 'package:dclix_app/theme/theme_provider.dart';
import 'package:dclix_app/widgets/club_tab_bar.dart';

/// The nine tiles from the bug report, and the screen each must actually show.
const _tabTiles = <String, Type>{
  'Training': TrainingScreen,
  "Today's Classes": ScheduleScreen,
  'Timetable': ScheduleScreen,
  'My Trainer': TrainingScreen,
  'Fees Due': PaymentsScreen,
  'Payment History': PaymentsScreen,
  'Advance Payment': PaymentsScreen,
  'Progress Report': ProgressScreen,
  'Profile': ProfileScreen,
};

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late http.Client original;

  setUp(() {
    original = ApiService.client;
    SharedPreferences.setMockInitialValues({});
    final s = UserSession.instance;
    s.authData = {'id': 1, 'studentId': 1, 'userType': 3, 'name': 'Test Member'};
    s.myInfo = {'name': 'Test Member', 'studentId': 1, 'currentGrade': 'Green Belt'};
    s.homeStats = {'invoiceCount': 0, 'dueAmount': 0};
    s.homeStatsError = null;
    s.outstandingList = [];
    s.activeStudentId = null;
    s.activeStudentName = null;
    s.loading = false;
    // Unstubbed, like the other real-screen tests: this is about which screen shows, not its
    // data. A blanket JSON reply would also be fed to Profile's QR Image.memory as "bytes".
    ApiService.client = MockClient((_) async => http.Response('not found', 404));
  });

  tearDown(() {
    ApiService.client = original;
    UserSession.instance.stopNotificationPolling();
  });

  for (final MapEntry(key: label, value: screen) in _tabTiles.entries) {
    testWidgets('All Features → $label shows $screen, and back returns to All Features', (tester) async {
      // 800dp wide, as screen_render_test renders Progress: the test font draws every glyph a
      // full em wide (~1.8x real text), so phone widths overflow spuriously on the Progress and
      // Advance Payment rows — layout this test isn't about. Tall enough that every catalogue
      // section builds without scrolling (the list is lazy).
      tester.view.physicalSize = const Size(2400, 7200);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      // The app's real routes, minus appRouter's login redirect.
      final router = GoRouter(initialLocation: '/home', routes: appRouter.configuration.routes);
      addTearDown(router.dispose);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: UserSession.instance),
          ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
      ));
      await _settle(tester);

      router.push('/more'); // the Home screen's "More" Quick Access tile
      await _settle(tester);
      expect(find.text('All Features'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byType(MoreScreen), matching: find.text(label)));
      await _settle(tester);

      expect(find.byType(screen), findsOneWidget, reason: '$label must render its screen, not a blank shell');
      expect(find.text('All Features'), findsNothing);

      // The header's chevron is the first on every screen; Advance Payment has a second one in
      // its year picker.
      await tester.tap(find.descendant(of: find.byType(screen), matching: find.byIcon(Ion.chevronBack)).first);
      await _settle(tester);

      expect(find.text('All Features'), findsOneWidget, reason: 'back from $label must return to All Features');
    });
  }

  testWidgets('inside the shell, All Features scrolls its last row clear of the tab bar', (tester) async {
    // Short enough that the catalogue has to scroll, with a gesture-bar inset under the tab bar.
    tester.view.physicalSize = const Size(2400, 2400);
    tester.view.devicePixelRatio = 3.0;
    tester.view.padding = const FakeViewPadding(bottom: 102);
    addTearDown(tester.view.reset);

    final router = GoRouter(initialLocation: '/home', routes: appRouter.configuration.routes);
    addTearDown(router.dispose);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UserSession.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
    ));
    await _settle(tester);
    router.push('/more');
    await _settle(tester);

    // A lazy list only knows its true extent once it has laid the tail out, so one long drag
    // stops short — keep going until the position is really at the end.
    final list = find.descendant(of: find.byType(MoreScreen), matching: find.byType(Scrollable)).first;
    final position = tester.state<ScrollableState>(list).position;
    for (var i = 0; i < 40 && position.pixels < position.maxScrollExtent; i++) {
      await tester.drag(list, const Offset(0, -300));
      await tester.pump();
    }
    await _settle(tester);
    expect(position.pixels, position.maxScrollExtent, reason: 'must be scrolled to the very end');

    final lastTile = find.ancestor(
        of: find.descendant(of: find.byType(MoreScreen), matching: find.text('Edit Profile')),
        matching: find.byType(Container));
    expect(tester.getRect(lastTile.first).bottom, lessThanOrEqualTo(tester.getRect(find.byType(ClubTabBar)).top),
        reason: 'the Account row must not end under the translucent tab bar');
  });
}
