import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dclix_app/screens/autopay_screen.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/autopay.dart';
import 'package:dclix_app/theme/ion.dart';
import 'package:dclix_app/widgets/gradient_button.dart';

typedef _Family = List<({int id, String name})>;

/// What the club's sign-in payload allows Auto Pay to pay.
const _clubTypes = ['Monthly', 'Registration'];

/// What /AutoPay/ConsentContent gives: one box, a version, no terms page.
const _consent = AutoPayConsent(version: 'consent-v7', checkboxes: [
  (key: 'cardholder', text: 'I am the cardholder or an authorised account user.'),
]);

/// Terms pages the screen asked to open.
final _opened = <Uri>[];

Future<void> _open(
  WidgetTester t,
  Future<AutoPayMandate> Function() load, {
  _Family family = const [],
  List<String> types = _clubTypes,
  Future<AutoPayConsent> Function()? consent,
}) async {
  _opened.clear();
  // Tall enough that the whole list builds. Wider than a phone because the test font draws
  // every glyph a full em wide; real fonts fit 390 pt (see tool/capture_guide_shots.dart).
  t.view.physicalSize = const Size(1800, 2800);
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
      home: AutoPayScreen(
          key: UniqueKey(),
          load: load,
          family: () async => family,
          clubTypes: () async => types,
          consent: consent ?? () async => _consent,
          openUrl: (u) async {
            _opened.add(u);
            return true;
          })));
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

/// Switch on, set a limit and continue past the setup sheet to the agreement.
Future<void> _setUp(WidgetTester t) async {
  await t.tap(find.byType(Switch));
  await t.pumpAndSettle();
  await t.enterText(find.byType(TextField), '170');
  await t.tap(find.text('Continue'));
  await t.pumpAndSettle();
}

/// Tick every box of the agreement and leave for Boost.
Future<void> _agree(WidgetTester t) async {
  while (find.byIcon(Ion.squareOutline).evaluate().isNotEmpty) {
    await t.tap(find.byIcon(Ion.squareOutline).first);
    await t.pump();
  }
  await t.tap(find.text('Subscribe'));
  await t.pumpAndSettle();
}

GradientButton _agreeButton(WidgetTester t) => t.widget<GradientButton>(
    find.widgetWithText(GradientButton, 'Subscribe'));

const _visa = AutoPayMandate(AutoPayState.active,
    brand: 'Visa',
    last4: '4242',
    expiry: '08/28',
    invoiceTypes: ['Monthly', 'Registration'],
    perChargeCap: 170);
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
    expect(find.text('Pays'), findsOneWidget);
    expect(find.text('Monthly, Registration'), findsOneWidget);
    expect(find.text('Limit per transaction'), findsOneWidget);
    expect(find.text('RM 170.00'), findsOneWidget);
    expect(find.text('Monthly amount'), findsNothing);
    expect(find.text('Pause'), findsOneWidget);
    expect(find.text('Disable'), findsOneWidget);
    expect(find.byType(Switch), findsNothing,
        reason: 'once on, Pause / Resume / Disable replace the switch');

    await _open(t, () async => _paused);
    expect(find.text('PAUSED'), findsOneWidget);
    expect(find.text('Resume'), findsOneWidget);
    expect(find.text('Pause'), findsNothing);
    expect(find.text('Pays'), findsNothing, reason: 'the server reported no plan');
    expect(find.text('Limit per transaction'), findsNothing);

    await _open(
        t,
        () async => const AutoPayMandate(AutoPayState.failed,
            brand: 'Visa', last4: '4242', reason: 'Card declined by the bank.'));
    expect(find.text('Card declined by the bank.'), findsOneWidget);
    expect(find.text('Update card'), findsOneWidget);
  });

  testWidgets(
      'turning on asks for a limit, shows the family is covered, and agrees before Boost',
      (t) async {
    final calls = _serve(() => http.Response('', 404));
    await _open(t, () async => AutoPayMandate.off,
        family: const [(id: 11, name: 'AISHA TAN'), (id: 12, name: 'OMAR TAN')]);

    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('Set up Auto Pay'), findsOneWidget);
    expect(find.text('LIMIT PER TRANSACTION'), findsOneWidget);
    expect(find.text('Auto Pay never takes more than this in one payment.'), findsOneWidget);
    expect(find.text('AISHA TAN'), findsOneWidget);
    expect(find.text('OMAR TAN'), findsOneWidget);
    expect(find.textContaining('covers everyone'), findsOneWidget);

    // No limit yet: stays on the sheet and says what is missing.
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Enter your limit per transaction.'), findsOneWidget);
    expect(find.text('Review and agree'), findsNothing);

    await t.enterText(find.byType(TextField), '170');
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();

    // The agreement comes first, and says what is being agreed to.
    expect(calls, isEmpty, reason: 'nothing is sent before the member agrees');
    expect(find.text('Review and agree'), findsOneWidget);
    expect(find.text('Pays: Monthly, Registration'), findsOneWidget);
    expect(find.text('Up to RM 170.00 per transaction'), findsOneWidget);
    expect(find.text('Covers: AISHA TAN, OMAR TAN'), findsOneWidget);
    expect(find.text('Card: saved on Boost\'s secure page'), findsOneWidget);
    expect(find.text('Turn it off any time: Auto Pay → Disable'), findsOneWidget);

    await _agree(t);

    expect(calls, hasLength(1));
    expect(calls.single.$1, '/AutoPay/Enable');
    expect(calls.single.$2, {
      'invoiceTypes': ['Monthly', 'Registration'],
      'perChargeCap': 170,
      'consentVersion': 'consent-v7',
    });
    expect(find.textContaining('not open yet'), findsOneWidget);
    expect(_switchOn(t), isFalse);
  });

  testWidgets('the club\'s invoice types start ticked, and only the ticked ones are sent',
      (t) async {
    final semantics = t.ensureSemantics();
    final calls = _serve(() => http.Response('', 404));
    await _open(t, () async => AutoPayMandate.off);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();

    expect(find.text('INVOICES TO PAY'), findsOneWidget);
    for (final type in _clubTypes) {
      final node = t.getSemantics(find.text(type));
      expect(
          node,
          isSemantics(
              label: type, hasCheckedState: true, isChecked: true, hasTapAction: true),
          reason: '$type is one checkbox to a screen reader, and starts ticked');
      expect(node.rect.height, greaterThanOrEqualTo(48), reason: 'the whole row is the target');
    }

    await t.tap(find.text('Registration')); // anywhere on the row
    await t.pump();
    expect(t.getSemantics(find.text('Registration')),
        isSemantics(label: 'Registration', hasCheckedState: true, isChecked: false));

    await t.enterText(find.byType(TextField), '170');
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    expect(find.text('Pays: Monthly'), findsOneWidget);
    await _agree(t);

    expect(calls.single.$2, {
      'invoiceTypes': ['Monthly'],
      'perChargeCap': 170,
      'consentVersion': 'consent-v7',
    });
    semantics.dispose();
  });

  testWidgets('leaving out every invoice type stops at the sheet with a reason', (t) async {
    final calls = _serve(() => http.Response('', 404));
    await _open(t, () async => AutoPayMandate.off);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();

    await t.tap(find.text('Monthly'));
    await t.tap(find.text('Registration'));
    await t.enterText(find.byType(TextField), '170');
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();

    expect(find.text('Choose at least one type of invoice.'), findsOneWidget);
    expect(find.text('Review and agree'), findsNothing);
    expect(calls, isEmpty);

    // Ticking one again clears it.
    await t.tap(find.text('Monthly'));
    await t.pump();
    expect(find.text('Choose at least one type of invoice.'), findsNothing);
  });

  testWidgets('a club that sent no invoice types is not asked about them', (t) async {
    final calls = _serve(() => http.Response('', 404));
    await _open(t, () async => AutoPayMandate.off, types: const []);
    await t.tap(find.byType(Switch));
    await t.pumpAndSettle();
    expect(find.text('INVOICES TO PAY'), findsNothing);

    await t.enterText(find.byType(TextField), '170');
    await t.tap(find.text('Continue'));
    await t.pumpAndSettle();
    await _agree(t);

    expect(calls.single.$2, {'perChargeCap': 170, 'consentVersion': 'consent-v7'},
        reason: 'no invoiceTypes at all, rather than an empty list that pays nothing');
  });

  testWidgets('Agree waits for the box to be ticked', (t) async {
    final calls = _serve(() => http.Response('', 404));
    await _open(t, () async => AutoPayMandate.off);
    await _setUp(t);

    expect(_agreeButton(t).onPressed, isNull);
    await t.tap(find.text('Subscribe'));
    await t.pumpAndSettle();
    expect(find.text('Review and agree'), findsOneWidget);
    expect(calls, isEmpty);

    await t.tap(find.byIcon(Ion.squareOutline));
    await t.pump();
    expect(_agreeButton(t).onPressed, isNotNull);
    await t.tap(find.byIcon(Ion.checkbox));
    await t.pump();
    expect(_agreeButton(t).onPressed, isNull, reason: 'unticking takes the agreement back');
  });

  testWidgets('the terms open from the agreement, without ticking it', (t) async {
    _serve(() => http.Response('', 404));
    await _open(t, () async => AutoPayMandate.off);
    await _setUp(t);

    await t.tap(find.text('Read the Recurring Billing Terms and Cancellation Policy'));
    await t.pumpAndSettle();
    for (final heading in [
      'What gets charged',
      'When you are charged',
      'Checking your card',
      'Receipts',
      'Pausing and resuming',
      'Cancelling',
      'If a payment fails',
      'Questions about a charge',
    ]) {
      expect(find.text(heading), findsOneWidget, reason: heading);
    }

    Navigator.of(t.element(find.text('Cancelling'))).pop();
    await t.pumpAndSettle();
    expect(find.text('Cancelling'), findsNothing);
    expect(_agreeButton(t).onPressed, isNull,
        reason: 'reading the terms is not agreeing to them');
  });

  testWidgets('backing out of the agreement sends nothing and leaves Auto Pay off',
      (t) async {
    final calls = _serve(() => http.Response('', 404));
    await _open(t, () async => AutoPayMandate.off);
    await _setUp(t);
    expect(find.text('Review and agree'), findsOneWidget);

    await t.tap(find.byIcon(Ion.chevronBack));
    await t.pumpAndSettle();

    expect(find.text('Review and agree'), findsNothing);
    expect(calls, isEmpty);
    expect(_switchOn(t), isFalse);
  });

  testWidgets('a new card is agreed to again, on the same plan', (t) async {
    final calls = _serve(() => http.Response('', 404));
    await _open(t, () async => _visa);

    await t.tap(find.text('Visa •••• 4242'));
    await t.pumpAndSettle();
    expect(find.text('Review and agree'), findsOneWidget);
    expect(calls, isEmpty);
    await _agree(t);

    expect(calls.single.$2, {
      'invoiceTypes': ['Monthly', 'Registration'],
      'perChargeCap': 170,
      'consentVersion': 'consent-v7',
    });
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

  testWidgets('Continue waits for the invoice types to arrive', (t) async {
    final types = Completer<List<String>>();
    t.view.physicalSize = const Size(1800, 2800);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
        home: AutoPayScreen(
            load: () async => AutoPayMandate.off,
            family: () async => const [],
            clubTypes: () => types.future)));
    await t.pumpAndSettle();
    await t.tap(find.byType(Switch));
    // Not pumpAndSettle: the "loading types" spinner turns until they arrive.
    await t.pump();
    await t.pump(const Duration(milliseconds: 500));

    GradientButton cont() => t.widget<GradientButton>(
        find.widgetWithText(GradientButton, 'Continue'));
    expect(cont().onPressed, isNull, reason: 'the choice is not known yet');

    types.complete(['Monthly', 'Grading']);
    await t.pumpAndSettle();
    expect(cont().onPressed, isNotNull);
    expect(find.text('Grading'), findsOneWidget);
  });

  for (final (state, m) in [('off', AutoPayMandate.off), ('on', _visa)]) {
    testWidgets('with Auto Pay $state, the terms and paying yourself are on the screen',
        (t) async {
      await _open(t, () async => m);
      await t.scrollUntilVisible(find.text('Recurring Billing Terms'), 200);
      expect(find.text('Pay yourself any time'), findsOneWidget,
          reason: 'manual payment works whether Auto Pay is on or off');

      await t.ensureVisible(find.text('Recurring Billing Terms'));
      await t.pumpAndSettle();
      await t.tap(find.text('Recurring Billing Terms'));
      await t.pumpAndSettle();
      expect(find.text('What gets charged'), findsOneWidget);
      expect(find.text('Paying yourself'), findsOneWidget);
    });
  }

  testWidgets('every box the server words must be ticked before Agree', (t) async {
    final calls = _serve(() => http.Response('', 404));
    await _open(t, () async => AutoPayMandate.off,
        consent: () async => const AutoPayConsent(version: 'v2', checkboxes: [
              (key: 'cardholder', text: 'I am the cardholder.'),
              (key: 'recurring', text: 'I agree to recurring billing.'),
            ]));
    await _setUp(t);
    expect(find.text('I am the cardholder.'), findsOneWidget);
    expect(find.text('I agree to recurring billing.'), findsOneWidget);

    await t.tap(find.text('I am the cardholder.'));
    await t.pump();
    expect(_agreeButton(t).onPressed, isNull, reason: 'one box is still open');

    await t.tap(find.text('I agree to recurring billing.'));
    await t.pump();
    await t.tap(find.text('Subscribe'));
    await t.pumpAndSettle();
    expect((calls.single.$2 as Map)['consentVersion'], 'v2',
        reason: 'the server records which wording was agreed to');
  });

  testWidgets('an agreement that will not load sends nothing, and can be retried',
      (t) async {
    final calls = _serve(() => http.Response('', 404));
    var tries = 0;
    await _open(t, () async => AutoPayMandate.off, consent: () async {
      if (tries++ == 0) throw Exception('offline');
      return _consent;
    });
    await _setUp(t);
    expect(find.text('Subscribe'), findsNothing);
    expect(calls, isEmpty);

    await t.tap(find.text('Try again'));
    await t.pumpAndSettle();
    expect(find.text('I am the cardholder or an authorised account user.'), findsOneWidget);
  });

  testWidgets('the club\'s terms page opens in the app when the server gives one',
      (t) async {
    _serve(() => http.Response('', 404));
    await _open(t, () async => AutoPayMandate.off,
        consent: () async => const AutoPayConsent(
            version: 'v1',
            checkboxes: [(key: 'k', text: 'I agree.')],
            termsUrl: 'https://club.example/autopay-terms'));
    await _setUp(t);

    await t.tap(find.text('Read the Recurring Billing Terms and Cancellation Policy'));
    await t.pumpAndSettle();
    expect(_opened, [Uri.parse('https://club.example/autopay-terms')]);
    expect(find.text('What gets charged'), findsNothing,
        reason: 'the club\'s own page, not the built-in summary');
  });

  testWidgets('the plan can be changed while on, keeping the card', (t) async {
    var m = _visa;
    final calls = _serve(() {
      m = const AutoPayMandate(AutoPayState.active,
          brand: 'Visa', last4: '4242', invoiceTypes: ['Monthly'], perChargeCap: 90);
      return _ok();
    });
    await _open(t, () async => m);

    await t.ensureVisible(find.text('Change what it pays'));
    await t.tap(find.text('Change what it pays'));
    await t.pumpAndSettle();
    expect(find.text('Change Auto Pay'), findsOneWidget);
    expect(find.text('170.00'), findsOneWidget, reason: 'the current limit is filled in');

    await t.enterText(find.byType(TextField), '90');
    await t.tap(find.text('Registration'));
    await t.pump();
    await t.tap(find.text('Save changes'));
    await t.pumpAndSettle();

    expect(calls.single.$1, '/AutoPay/UpdateSettings');
    expect(calls.single.$2, {'invoiceTypes': ['Monthly'], 'perChargeCap': 90});
    expect(find.text('Review and agree'), findsNothing, reason: 'same card, no new agreement');
    expect(find.text('Auto Pay updated. Your card stays the same.'), findsOneWidget);
  });
}

