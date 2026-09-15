// Every tile the member can tap must land somewhere.
//
// The catalogue and the home grid are plain data, and the router is a separate list of
// paths — nothing in the type system connects the two. A route renamed on one side and
// not the other compiles clean, ships, and shows up only when a member taps a tile and
// nothing happens. These tests close that gap.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dclix_app/router/app_router.dart';
import 'package:dclix_app/screens/instructor_reports_screen.dart';
import 'package:dclix_app/screens/more_screen.dart';
import 'package:dclix_app/screens/home_screen.dart';

/// Flatten the router tree (ShellRoutes nest their children) into the set of paths.
Set<String> _registeredPaths(List<RouteBase> routes) {
  final out = <String>{};
  void walk(List<RouteBase> rs) {
    for (final r in rs) {
      if (r is GoRoute) out.add(r.path);
      walk(r.routes);
    }
  }

  walk(routes);
  return out;
}

void main() {
  // Constructing a GoRouter initialises the widgets binding, and doing that before
  // flutter_test claims its own binding aborts the whole file. Claim it first.
  TestWidgetsFlutterBinding.ensureInitialized();

  final registered = _registeredPaths(appRouter.configuration.routes);

  test('the router itself exposes the paths we expect to match against', () {
    // Guards the walker: if go_router changes its tree shape this fails loudly
    // rather than silently reporting "no dead links" over an empty set.
    expect(registered, contains('/home'));
    expect(registered, contains('/more'));
    expect(registered.length, greaterThan(15));
  });

  test('Competition is renamed Tournament, with old links redirected', () {
    expect(registered, contains('/tournament'));
    expect(MoreScreen.catalogueRoutes, isNot(contains('/competition')));
    expect(kStudentQuickCards.map((q) => q.route), isNot(contains('/competition')));
    for (final (from, to) in const [
      ('/competition', '/tournament'),
      ('/instructor/reports/tournament-past', '/instructor/reports/tournament-summary'),
      ('/instructor/reports/tournament-upcoming', '/instructor/reports/tournament-summary'),
    ]) {
      final route = appRouter.configuration.routes.whereType<GoRoute>().firstWhere((r) => r.path == from);
      expect(route.redirect, isNotNull, reason: '$from must redirect');
      expect(route.redirect!(_FakeContext(), _FakeState()), to);
    }
  });

  test('every More-catalogue tile points at a registered route', () {
    final dead = MoreScreen.catalogueRoutes
        .where((r) => !registered.contains(Uri.parse(r).path))
        .toSet();
    expect(dead, isEmpty,
        reason: 'dead tiles in the All Features catalogue: $dead');
  });

  test('every instructor report tile points at a registered route', () {
    final dead = kInstructorReports.map((r) => r.route)
        .where((r) => !registered.contains(Uri.parse(r).path))
        .toSet();
    expect(dead, isEmpty,
        reason: 'dead tiles on the instructor reports list: $dead');
  });

  test('every home quick-access tile points at a registered route', () {
    final dead = kStudentQuickCards
        .map((q) => q.route)
        .where((r) => !registered.contains(Uri.parse(r).path));
    expect(dead, isEmpty, reason: 'dead tiles on the home grid: $dead');
  });

  test('the catalogue is the only way to reach the screens with no home tile',
      () {
    // These have no quick-access tile of their own, so losing them from the catalogue
    // would strand the screen with no entry point anywhere in the app.
    final quick = kStudentQuickCards.map((q) => q.route).toSet();
    // /invoices (Pay Your Dues) is instructor-only: reached from the Reports tab and the
    // instructor home dues card, as in Expo v2.11.1 — not from the student catalogue.
    for (final orphan in ['/book-class', '/notification-settings']) {
      expect(quick, isNot(contains(orphan)));
      expect(MoreScreen.catalogueRoutes, contains(orphan),
          reason: '$orphan would be unreachable');
    }
  });

  testWidgets('the catalogue renders every section and tile', (tester) async {
    // GridViews nested inside a ListView are an easy way to throw an unbounded-height
    // exception; render it once so a layout mistake fails here, not on a member's phone.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(home: MoreScreen()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('All Features'), findsOneWidget);
    expect(find.text('TRAINING'), findsOneWidget);
    expect(find.text('Book a Class'), findsOneWidget);

    // The list is lazy, so the lower sections only build once scrolled to. Walking to
    // each one also exercises the nested-GridView layout at every offset.
    //
    // The list is lazy, so the lower sections only build once scrolled to. Walking to
    // each one also exercises the nested-GridView layout at every offset.
    //
    // A hand-rolled drag loop rather than scrollUntilVisible: each section's GridView is
    // itself a (non-scrolling) Scrollable, and the interaction between that and the
    // helper's own finder handling made it throw "Bad state: No element" on a section
    // that plain drags reach without trouble.
    Future<void> scrollTo(String text) async {
      for (var i = 0; i < 40 && find.text(text).evaluate().isEmpty; i++) {
        await tester.drag(find.byType(Scrollable).first, const Offset(0, -250));
        await tester.pump();
      }
    }

    for (final section in ['PAYMENTS', 'PROGRESS', 'CLUB', 'ACCOUNT']) {
      await scrollTo(section);
      expect(find.text(section), findsOneWidget,
          reason: '$section heading missing');
    }
    await scrollTo('Profile');
    expect(find.text('Profile'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _FakeContext extends Fake implements BuildContext {}

class _FakeState extends Fake implements GoRouterState {}
