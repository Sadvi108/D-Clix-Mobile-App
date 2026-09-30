import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dclix_app/screens/autopay_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/autopay.dart';

Future<void> _open(WidgetTester t, AutoPayMandate m) async {
  // Tall enough that the whole list builds. Wider than a phone because the test font draws
  // every glyph a full em wide; real fonts fit 390 pt (see tool/capture_guide_shots.dart).
  t.view.physicalSize = const Size(1800, 2532);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: AutoPayScreen(key: UniqueKey(), load: () async => m)));
  await t.pumpAndSettle();
}

bool _switchOn(WidgetTester t) => t.widget<Switch>(find.byType(Switch)).value;

const _visa = AutoPayMandate(AutoPayState.active,
    brand: 'Visa', last4: '4242', expiry: '08/28');

void main() {
  testWidgets('each state says what it is', (t) async {
    await _open(t, AutoPayMandate.off);
    expect(find.text('Never miss a monthly fee'), findsOneWidget);
    expect(find.text('How it works'.toUpperCase()), findsOneWidget);
    expect(_switchOn(t), isFalse);

    await _open(t, _visa);
    expect(find.text('Auto Pay is on'), findsOneWidget);
    expect(find.text('Visa •••• 4242 is paying your invoices.'), findsOneWidget);
    expect(find.text('Visa •••• 4242'), findsOneWidget);
    expect(find.text('Expires 08/28'), findsOneWidget);
    expect(_switchOn(t), isTrue);

    await _open(t, const AutoPayMandate(AutoPayState.pending));
    expect(find.text('PENDING'), findsOneWidget);
    expect(find.text('On — confirming your card'), findsOneWidget);

    await _open(
        t,
        const AutoPayMandate(AutoPayState.failed,
            brand: 'Visa', last4: '4242', reason: 'Card declined by the bank.'));
    expect(find.text('Card declined by the bank.'), findsOneWidget);
    expect(find.text('Update card'), findsOneWidget);
  });

  testWidgets('switching on asks the server for Boost, and says so when not deployed',
      (t) async {
    final original = ApiService.client;
    addTearDown(() => ApiService.client = original);
    String? asked;
    ApiService.client = MockClient((req) async {
      asked = req.url.path;
      return http.Response('', 404);
    });

    await _open(t, AutoPayMandate.off);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();

    expect(asked, '/AutoPay/Enable');
    expect(find.textContaining('not open yet'), findsOneWidget);
    expect(_switchOn(t), isFalse);
  });

  testWidgets('switching off asks before removing the card', (t) async {
    await _open(t, _visa);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Remove your card?'), findsOneWidget);

    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(_switchOn(t), isTrue);
  });

  testWidgets('Yes, remove unlinks the card and says so', (t) async {
    final original = ApiService.client;
    addTearDown(() => ApiService.client = original);
    var m = _visa;
    String? asked;
    ApiService.client = MockClient((req) async {
      asked = req.url.path;
      m = AutoPayMandate.off; // what the server reports once the card is gone
      return http.Response('{"status":200,"meta":{"code":200},"data":null}', 200,
          headers: {'content-type': 'application/json'});
    });

    t.view.physicalSize = const Size(1800, 2532);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(home: AutoPayScreen(load: () async => m)));
    await t.pumpAndSettle();

    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes, remove'));
    await t.pumpAndSettle();

    expect(asked, '/AutoPay/Disable');
    expect(find.text('Card removed. Auto Pay is off.'), findsOneWidget);
    expect(_switchOn(t), isFalse);
  });
}
