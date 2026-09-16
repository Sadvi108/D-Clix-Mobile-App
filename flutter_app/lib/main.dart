import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'router/app_router.dart';
import 'services/extra_trust.dart';
import 'services/user_session.dart';
import 'services/notification_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Before any request: older Android phones cannot verify the photo host otherwise.
  await ExtraTrust.install();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider<UserSession>.value(value: UserSession.instance),
      ],
      child: const DClixApp(),
    ),
  );
}

class DClixApp extends StatefulWidget {
  const DClixApp({super.key});
  @override
  State<DClixApp> createState() => _DClixAppState();
}

class _DClixAppState extends State<DClixApp> {
  AppLifecycleListener? _lifecycle;
  String? _pendingNotification;
  bool _navigationQueued = false;

  @override
  void initState() {
    super.initState();
    NotificationService.onTap = (payload) {
      _pendingNotification = payload ?? 'chat';
      _sessionChanged();
    };
    UserSession.instance.addListener(_sessionChanged);
    _lifecycle = AppLifecycleListener(onResume: () {
      if (UserSession.instance.isLoggedIn)
        UserSession.instance.startNotificationPolling();
    }, onStateChange: (state) {
      if (state != AppLifecycleState.resumed)
        UserSession.instance.stopNotificationPolling();
    });
  }

  void _sessionChanged() {
    final session = UserSession.instance;
    if (_pendingNotification == null ||
        !session.isLoggedIn ||
        session.loading ||
        _navigationQueued) return;
    _navigationQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _navigationQueued = false;
      if (!mounted || !session.isLoggedIn || session.loading) return;
      final payload = _pendingNotification;
      _pendingNotification = null;
      appRouter.push(payload == 'autopay' ? '/autopay' : '/chat');
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    UserSession.instance.removeListener(_sessionChanged);
    NotificationService.onTap = null;
    UserSession.instance.stopNotificationPolling();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'D-Clix',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: themeProvider.mode,
      routerConfig: appRouter,
      scaffoldMessengerKey: UserSession.scaffoldMessengerKey,
      // Allow drag-to-scroll from every pointer (touch, mouse, trackpad,
      // stylus). Keeps scrolling smooth on phones and makes the web/desktop
      // preview behave like a real device instead of needing a wheel.
      scrollBehavior: const _AppScrollBehavior(),
      // Clamp the OS text scale to a range the layouts are designed for.
      // Below 0.85 text becomes unreadable; above ~1.3 fixed-height cards
      // overflow. This single guard keeps every screen responsive to a
      // user's accessibility font setting without per-screen rework.
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        final clamped = mq.textScaler.clamp(
          minScaleFactor: 0.85,
          maxScaleFactor: 1.30,
        );
        return MediaQuery(
          data: mq.copyWith(textScaler: clamped),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
  }
}

/// Enables drag scrolling from all pointer kinds (the Material default omits
/// mouse + trackpad, which makes web/desktop scrolling feel broken).
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}
