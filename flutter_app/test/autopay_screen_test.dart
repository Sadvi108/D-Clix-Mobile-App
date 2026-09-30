import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dclix_app/screens/autopay_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/autopay.dart';

typedef _Family = List<({int id, String name})>;

Future<void> _open(
  WidgetTester t,
  Future<AutoPayMandate> Function() load, {
  _Family family = const [],
}) async {
  // Tall enough that the whole list builds. Wider than a phone because the test font draws
  // every glyph a full em wide; real fonts fit 390 pt (see tool/capture_guide_shots.dart).
  t.view.physicalSize = const Size(1800, 2800);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
      home: AutoPayScreen(
          key: UniqueKey(), load: load, family: () async => family)));
  await t.pumpAndSettle();
}

/// Serve every request with [reply], recording the path and decoded body.
List<(String, Object?)> _serve(http.Response Function() reply) {
  final original = ApiService.client;
  addTearDown(() => ApiService.client = original);
  final calls = <(String, Object?)>[];
  ApiService.client = MockClient((req) async {
    calls.add((req.url.path, req.body.isEmpty ? null : jsonDecode(req.body)));
    return reply();
  });
  return calls;
}

http.Response _ok() => http.Response('{"status":200,"meta":{"code":200},"data":null}', 200,
    headers: {'content-type': 'application/json'});

bool _switchOn(WidgetTester t) => t.widget<Switch>(find.byType(Switch)).value;

const _visa = AutoPayMandate(AutoPayState.active,
    brand: 'Visa', last4: '4242', expiry: '08/28', monthlyAmount: 170);
const _paused = AutoPayMandate(AutoPayState.paused, brand: 'Visa', last4: '4242');

void main() {
  testWidgets('each state says what it is, with the controls that fit it', (t) async {
    await _open(t, () async => AutoPayMandate.off);
    expect(find.text('Never miss a monthly fee'), findsOneWidget);
    expect(_switchOn(t), isFalse);
    expect(find.text('Pause'), findsNothing);

    await _open(t, () async => _visa);
    expect(find.text('Visa •••• 4242 is paying your invoices.'), findsOneWidget);
    expect(find.text('Expires 08/28'), findsOneWidget);
    expect(find.text('RM 170.00'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Disable'), findsOneWidget);
    expect(find.byType(Switch), findsNothing,
        reason: 'once on, Pause / Resume / Disable replace the switch');

    await _open(t, () async => _paused);
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);

    await _open(
        t,
        () async => const AutoPayMandate(AutoPayState.failed,
            brand: 'Visa', last4: '4242', reason: 'Card declined by the bank.'));
    expect(find.text('Card declined by the bank.'), findsOneWidget);
    expect(find.text('Update card'), findsOneWidget);
  });

  testWidgets('turning on asks the amount and shows the whole family is covered',
      (t) async {
    final calls = _serve(() => http.Response('', 404));
    await _open(t, () async => AutoPayMandate.off,
        family: const [(id: 11, name: 'AISHA TAN'), (id: 12, name: 'OMAR TAN')]);

    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Set up Auto Pay'), findsOneWidget);
    expect(find.text('AISHA TAN'), findsOneWidget);
    expect(find.text('OMAR TAN'), findsOneWidget);
    expect(find.textContaining('covers everyone'), findsOneWidget);

    // No amount yet: stays on the sheet and says what is missing.
    await t.tap(find.text('Continue to Boost'));
    await t.pumpAndSettle();
    expect(find.text('Enter the amount to take each month.'), findsOneWidget);
    expect(calls, isEmpty);

    await t.enterText(find.byType(TextField), '170');
    await t.tap(find.text('Continue to Boost'));
    await t.pumpAndSettle();

    expect(calls, hasLength(1));
    expect(calls.single.$1, '/AutoPay/Enable');
    expect(calls.single.$2, {'monthlyAmount': 170, 'studentIds': [11, 12]});
    expect(find.textContaining('not open yet'), findsOneWidget);
    expect(_switchOn(t), isFalse);
  });

  testWidgets('a single-member account is not shown a family list', (t) async {
    await _open(t, () async => AutoPayMandate.off,
        family: const [(id: 11, name: 'AISHA TAN')]);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Set up Auto Pay'), findsOneWidget);
    expect(find.textContaining('covers everyone'), findsNothing);
  });

  testWidgets('Pause asks first, then holds payments', (t) async {
    var m = _visa;
    final calls = _serve(() {
      m = _paused;
      return _ok();
    });
    await _open(t, () async => m);

    await t.tap(find.text('Pause'));
    await t.pumpAndSettle();
    expect(find.text('Pause Auto Pay?'), findsOneWidget);
    await t.tap(find.text('Yes, pause'));
    await t.pumpAndSettle();

    expect(calls.single.$1, '/AutoPay/Pause');
    expect(find.text('Auto Pay paused. Your card stays saved.'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
  });

  testWidgets('Resume brings payments back', (t) async {
    var m = _paused;
    final calls = _serve(() {
      m = _visa;
      return _ok();
    });
    await _open(t, () async => m);

    await t.tap(find.text('Resume'));
    await t.pumpAndSettle();

    expect(calls.single.$1, '/AutoPay/Resume');
    expect(find.text('Auto Pay resumed.'), findsOneWidget);
    expect(find.text('Pause'), findsOneWidget);
  });

  testWidgets('Disable asks before removing the card', (t) async {
    await _open(t, () async => _visa);
    await t.tap(find.text('Disable'));
    await t.pumpAndSettle();
    expect(find.text('Remove your card?'), findsOneWidget);

    await t.tap(find.text('Cancel'));
    await t.pumpAndSettle();
    expect(find.text('Pause'), findsOneWidget, reason: 'still on');
  });

  testWidgets('Yes, remove unlinks the card and says so', (t) async {
    var m = _visa;
    final calls = _serve(() {
      m = AutoPayMandate.off; // what the server reports once the card is gone
      return _ok();
    });
    await _open(t, () async => m);

    await t.tap(find.text('Disable'));
    await t.pumpAndSettle();
    await t.tap(find.text('Yes, remove'));
    await t.pumpAndSettle();

    expect(calls.single.$1, '/AutoPay/Disable');
    expect(find.text('Card removed. Auto Pay is off.'), findsOneWidget);
    expect(_switchOn(t), isFalse);
  });
}
