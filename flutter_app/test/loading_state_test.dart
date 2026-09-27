// A screen must always leave its loading state.
//
// NotificationSettingsScreen (and the old reminder-based Auto Pay) awaited
// NotificationService.init(), which could throw — and had no catch. The screen then sat on
// a spinner forever, with no error, no retry and no way out. In a widget test the plugin's platform interface
// is never registered and `instance` throws LateInitializationError, which reproduces the
// device failure modes (dead channel, OEM quirk) exactly.
//
// So this test runs WITHOUT any notification channel mock on purpose: the plugin failing
// is the condition under test.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/screens/autopay_screen.dart';
import 'package:dclix_app/screens/notification_settings_screen.dart';
import 'package:dclix_app/services/notification_service.dart';
import 'package:dclix_app/services/user_session.dart';
import 'package:dclix_app/widgets/rn_kit.dart';

Widget _wrap(Widget child) => ChangeNotifierProvider<UserSession>.value(
      value: UserSession.instance,
      child: MaterialApp(home: child),
    );

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NotificationService.resetForTest();
  });

  testWidgets('Auto Pay leaves the spinner when its status call fails', (tester) async {
    await tester.pumpWidget(_wrap(AutoPayScreen(load: () async => throw Exception('offline'))));
    await _settle(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'stuck on the loading state with no error and no way out');
    expect(find.byType(ErrorState), findsOneWidget);
  });

  testWidgets('Notification settings leaves the spinner too', (tester) async {
    await tester.pumpWidget(_wrap(const NotificationSettingsScreen()));
    await _settle(tester);

    expect(find.byType(CircularProgressIndicator), findsNothing,
        reason: 'stuck on the loading state with no error and no way out');
  });

  test('a failed init reports unavailable rather than throwing', () async {
    NotificationService.resetForTest();
    // Must not throw, whatever the platform does.
    await NotificationService.init();
    expect(NotificationService.isAvailable, isFalse);
    expect(await NotificationService.hasPermission(), isFalse);
  });
}
