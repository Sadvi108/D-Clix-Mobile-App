// The /debug screen must not exist in a release build.
//
// It dumps the whole session — the bearer token included — with a copy-to-clipboard button,
// and it was registered unconditionally and exempted from the sign-in redirect. On a phone
// nothing linked to it, but the web build opened it at #/debug. Developer screens are now
// registered only when kDebugMode is set.
//
// `flutter test` always runs in debug mode, so these tests drive the release side through the
// explicit flags rather than kDebugMode itself.
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:dclix_app/router/app_router.dart';

Set<String> _paths(List<RouteBase> routes) => {
      for (final r in routes)
        if (r is GoRoute) r.path,
      for (final r in routes) ..._paths(r.routes),
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a release build registers no developer routes', () {
    expect(developerRoutes(enabled: false), isEmpty);
  });

  test('a debug build still gets the /debug dump', () {
    expect(_paths(developerRoutes(enabled: true)), {'/debug'});
  });

  test('outside debug builds /debug is not reachable without signing in', () {
    expect(publicPaths(developerTools: false), isNot(contains('/debug')));
    expect(publicPaths(developerTools: false), containsAll(['/', '/login', '/user-guide']));
  });

  test('the app router takes its developer routes from the kDebugMode gate', () {
    expect(_paths(appRouter.configuration.routes).contains('/debug'), kDebugMode);
    expect(publicPaths().contains('/debug'), kDebugMode);
  });
}
