// The launch intro: orange ring -> D/CLIX word -> badge -> glide into Login.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/screens/login_screen.dart';
import 'package:dclix_app/screens/splash_screen.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:dclix_app/theme/theme_provider.dart';

Widget _app({bool reduceMotion = false}) => ChangeNotifierProvider<UserSession>.value(
      value: UserSession.instance,
      child: MaterialApp.router(
        theme: AppTheme.light(),
        builder: (context, child) =>
            MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion), child: child!),
        routerConfig: GoRouter(routes: [
          GoRoute(path: '/', builder: (_, __) => const SplashScreen()),
          GoRoute(path: '/login', builder: (_, __) => const Scaffold(body: Text('login page'))),
        ]),
      ),
    );

Future<void> _advance(WidgetTester tester, int ms) async {
  for (var i = 0; i < ms ~/ 50; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('the ring draws itself, then each arc straightens into its glyph', () {
    expect(wordStrokes, hasLength(8));
    expect(wordStrokes.first.a0, 180, reason: 'the ring starts on its left side');
    expect(wordStrokes.last.a1, closeTo(540, 1e-9), reason: 'the eight arcs make one full ring');
    for (final s in wordStrokes) {
      expect(s.at(0), isNull, reason: 'nothing shows before the ring starts drawing');
      for (final p in s.at(kIntroRingDrawnAt)!.pts) {
        expect((p - const Offset(50, 50)).distance, closeTo(39.5, 1e-6));
      }
      expect(s.at(kIntroWordAt)!.pts, s.to);
      expect(s.to.every((p) => p.dx.isFinite && p.dy.isFinite), isTrue);
    }
    expect(wordStrokes.where((s) => s.ink == StrokeInk.slash), hasLength(1));
  });

  test('every frame of both exits paints, in both themes', () {
    for (final colors in [AppColors.light, AppColors.dark]) {
      for (final toLogin in [true, false]) {
        final clock = IntroClock()..toLogin = toLogin;
        final painter = IntroPainter(
          clock: clock,
          colors: colors,
          logo: null,
          logoTarget: const Rect.fromLTWH(20, 67, 38, 38),
          wordTarget: const Rect.fromLTWH(68, 77, 70, 17),
          text: const TextStyle(),
        );
        for (var t = 0.0; t <= kIntroExitMin + kIntroGlideMs; t += 20) {
          clock
            ..t = t
            ..exitAt = t >= kIntroExitMin ? kIntroExitMin : null;
          final rec = ui.PictureRecorder();
          painter.paint(Canvas(rec), const Size(390, 844));
          rec.endRecording().dispose();
        }
      }
    }
  });

  testWidgets('plays the whole intro, then opens Login when no session is saved', (tester) async {
    await tester.pumpWidget(_app());
    await _advance(tester, 2100);
    expect(find.text('login page'), findsNothing, reason: 'the intro is still playing');
    await _advance(tester, 900);
    await tester.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets('with Reduce Motion it skips the animation', (tester) async {
    await tester.pumpWidget(_app(reduceMotion: true));
    await _advance(tester, 300);
    await tester.pumpAndSettle();
    expect(find.text('login page'), findsOneWidget);
  });

  testWidgets('the glide lands exactly on the Login header', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844)
      ..devicePixelRatio = 1
      ..padding = const FakeViewPadding(top: 47);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: UserSession.instance),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: const LoginScreen()),
    ));
    await tester.pump();
    final ctx = tester.element(find.byType(LoginScreen));
    final safe = MediaQuery.paddingOf(ctx);
    final logo = find.byWidgetPredicate((w) => w is Image && w.image is AssetImage && (w.image as AssetImage).assetName == kLogoAssetPath);
    expect(tester.getRect(logo), loginLogoRect(safe));
    final word = tester.getRect(find.text('D-CLIX'));
    final target = loginWordRect(safe, Theme.of(ctx).textTheme.bodyMedium!);
    expect(word.topLeft, offsetMoreOrLessEquals(target.topLeft, epsilon: 0.5));
    expect(word.size.width, moreOrLessEquals(target.width, epsilon: 0.5));
  });
}
