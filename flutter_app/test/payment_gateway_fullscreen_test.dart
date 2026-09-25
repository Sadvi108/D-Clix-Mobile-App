// The Boost checkout must not open underneath the tab bar.
//
// Every payment entry point but /invoices lives inside a `ShellRoute`, so
// `Navigator.of(context).push` from one of them lands on the SHELL navigator — inside
// `TabsShell`, whose `extendBody: true` Scaffold keeps the frosted ClubTabBar painted
// across the bottom of whatever it hosts. FPX draws its Pay and Cancel buttons exactly
// there, so the bar sat on top of them: a member who had already been quoted an amount
// could neither confirm the payment nor cancel it.
//
// The fix is one entry point, [BcpgWebViewScreen.open], that pushes on the ROOT navigator
// so the gateway covers the shell, tab bar included, until it pops. This test guards both
// halves — the helper stays a root push, and no screen goes around it.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Files that legitimately mention the screen's constructor: the screen itself.
const _declaringFile = 'lib/screens/payment/bcpg_webview_screen.dart';

Iterable<File> _libDartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('the gateway is pushed on the root navigator, above the tab shell', () {
    final src = File(_declaringFile).readAsStringSync();
    expect(src, contains('Navigator.of(context, rootNavigator: true)'),
        reason:
            'BcpgWebViewScreen.open must push on the root navigator; the shell navigator '
            'leaves ClubTabBar painted over the gateway\'s Pay and Cancel buttons.');
    expect(src, contains('static Future<Map<String, dynamic>?> open('),
        reason: 'The call sites below all route through open().');
  });

  test('no screen opens the gateway around that helper', () {
    final offenders = <String>[];
    for (final f in _libDartFiles()) {
      final path = f.path.replaceAll('\\', '/');
      if (path == _declaringFile) continue;
      final src = f.readAsStringSync();
      // `BcpgWebViewScreen(` is the constructor; `BcpgWebViewScreen.open(` and
      // `BcpgWebViewScreen.isMerchantReturn(` are the members callers may use.
      if (RegExp(r'BcpgWebViewScreen\s*\(').hasMatch(src)) offenders.add(path);
    }
    expect(offenders, isEmpty,
        reason:
            'These build the checkout screen themselves, so nothing guarantees it is '
            'pushed above the tab shell. Call BcpgWebViewScreen.open(context, ...).');
  });

  test('the gateway body clears the system navigation inset', () {
    final src = File(_declaringFile).readAsStringSync();
    expect(src, contains('body: SafeArea('),
        reason:
            'The gateway draws its buttons at the very bottom of the page; without the '
            'bottom inset they end up under the system navigation bar.');
  });
}
