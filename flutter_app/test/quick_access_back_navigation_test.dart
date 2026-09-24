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
import 'package:dclix_app/screens/more_screen.dart';

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

  testWidgets('Progress Report opened from All Features pops back to All Features, not Home', (tester) async {
    // Tall enough that the catalogue's Progress section (Training + Payments come first)
    // is on-screen without scrolling — the ListView is lazy, so an off-screen tile never builds.
    tester.view.physicalSize = const Size(1080, 3600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    final router = GoRouter(initialLocation: '/home', routes: [
      GoRoute(
        path: '/home',
        builder: (_, __) => Scaffold(
          body: Builder(builder: (ctx) => TextButton(onPressed: () => ctx.push('/more'), child: const Text('More'))),
        ),
      ),
      GoRoute(path: '/more', builder: (_, __) => const MoreScreen()),
      GoRoute(path: '/progress', builder: (_, __) => const Scaffold(body: Text('Progress Screen'))),
    ]);

    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('All Features'), findsOneWidget);

    await tester.tap(find.text('Progress Report'));
    await tester.pumpAndSettle();
    expect(find.text('Progress Screen'), findsOneWidget);

    // The back chevron calls safeBack(context), which pops when canPop() is true.
    final ctx = tester.element(find.text('Progress Screen'));
    expect(ctx.canPop(), isTrue);
    ctx.pop();
    await tester.pumpAndSettle();

    expect(find.text('All Features'), findsOneWidget,
        reason: 'back from Progress Report must return to All Features, not fall through to Home');
    expect(find.text('More'), findsNothing);
  });

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
