// Manual QA 2026-09-24, bugs 1-3: Quick Access / All Features drill-downs used `context.go`,
// which replaces the nav stack — so tapping Today's Classes, My Trainer, Timetable, Fees Due,
// Payment History or Profile from Quick Access left nothing to pop back to, and opening
// Progress Report from All Features wiped the pushed /more page so its back chevron fell
// through to the dashboard instead. The Payment History tile also pointed at the Pay tab
// instead of History. See lib/screens/home_screen.dart `openRoute`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dclix_app/screens/home_screen.dart';

void main() {
  testWidgets('a Quick Access tab-route destination stays poppable back to Home', (tester) async {
    // /schedule is one of the destinations that used to be a `_tabRoutes` entry switched with
    // `go`; any of the six bug-1 destinations would have failed the same way.
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => openRoute(ctx, '/schedule'),
              child: const Text('Timetable'),
            ),
          ),
        ),
      ),
      GoRoute(path: '/schedule', builder: (_, __) => const Scaffold(body: Text('Schedule Screen'))),
    ]);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Timetable'));
    await tester.pumpAndSettle();

    expect(find.text('Schedule Screen'), findsOneWidget);
    final ctx = tester.element(find.text('Schedule Screen'));
    expect(ctx.canPop(), isTrue, reason: 'Quick Access must push, not go, so there is a back control');
  });

  // All Features → tab screens (and back) is covered against the app's real routes in
  // more_tab_destinations_test.dart. A flat toy router here passed while the real app showed a
  // blank screen: it had no ShellRoute, and the bug only exists across the shell boundary.

  testWidgets('the Quick Access Payment History tile opens Payments on the History tab', (tester) async {
    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => openRoute(
                  ctx, kStudentQuickCards.firstWhere((q) => q.id == 'payments').route),
              child: const Text('Payment History'),
            ),
          ),
        ),
      ),
      // Mirrors the query-param handoff in lib/router/app_router.dart's /payments GoRoute.
      GoRoute(
        path: '/payments',
        builder: (_, s) => Scaffold(body: Text('tab=${s.uri.queryParameters['tab'] ?? 'pay'}')),
      ),
    ]);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('Payment History'));
    await tester.pumpAndSettle();

    expect(find.text('tab=history'), findsOneWidget);
  });

  test('the Fees Due tile still lands on the Pay tab', () {
    expect(kStudentQuickCards.firstWhere((q) => q.id == 'fees').route, '/payments');
  });
}
