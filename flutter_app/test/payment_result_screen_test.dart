import 'package:dclix_app/screens/payment/payment_result_screen.dart';
import 'package:dclix_app/services/boost_payment.dart';
import 'package:dclix_app/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _paid = PaymentResult(PaymentOutcome.paid, '');
const _unpaid = PaymentResult(PaymentOutcome.unpaid, '');
const _unknown = PaymentResult(PaymentOutcome.unknown, '');

void main() {
  group('paymentResultKind', () {
    test('the server saying paid wins over anything the page said', () {
      expect(paymentResultKind(_paid, null), PaymentResultKind.success);
      expect(paymentResultKind(_paid, 'failed'), PaymentResultKind.success);
    });

    test('Boost said success but the invoices are still due: processing, never failed', () {
      expect(paymentResultKind(_unpaid, 'success'), PaymentResultKind.pending);
      expect(paymentResultKind(_unknown, 'success'), PaymentResultKind.pending);
    });

    test('Boost said failed, or the invoices are still due', () {
      expect(paymentResultKind(_unknown, 'failed'), PaymentResultKind.failed);
      expect(paymentResultKind(_unpaid, 'failed'), PaymentResultKind.failed);
      expect(paymentResultKind(_unpaid, null), PaymentResultKind.failed);
    });

    test('closed the page and nothing was paid: cancelled', () {
      expect(paymentResultKind(_unpaid, 'cancelled'), PaymentResultKind.cancelled);
    });

    test('nothing can be proved either way: processing', () {
      expect(paymentResultKind(_unknown, null), PaymentResultKind.pending);
      expect(paymentResultKind(_unknown, 'cancelled'), PaymentResultKind.pending);
    });
  });

  Future<void> pump(WidgetTester t, PaymentResultKind kind) => t.pumpWidget(MaterialApp(
        theme: AppTheme.light(),
        home: PaymentResultScreen(
          key: UniqueKey(),
          kind: kind,
          amount: 170,
          paidFor: '2 invoices',
          reference: 'REF123',
          at: DateTime(2026, 10, 3, 20, 30),
        ),
      ));

  testWidgets('success shows the amount, what it paid and Done', (t) async {
    await pump(t, PaymentResultKind.success);
    expect(find.text('Payment successful'), findsOneWidget);
    expect(find.text('RM 170.00'), findsOneWidget);
    expect(find.text('2 invoices'), findsOneWidget);
    expect(find.text('REF123'), findsOneWidget);
    expect(find.text('3 Oct 2026, 8:30 PM'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('failed and cancelled offer Try again; processing warns before paying again',
      (t) async {
    await pump(t, PaymentResultKind.failed);
    expect(find.text('Payment failed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await pump(t, PaymentResultKind.cancelled);
    expect(find.text('Payment cancelled'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await pump(t, PaymentResultKind.pending);
    expect(find.text('Payment processing'), findsOneWidget);
    expect(find.textContaining('Check Payment History before paying again'), findsOneWidget);
    expect(find.text('Done'), findsOneWidget);
  });

  testWidgets('the button closes the screen', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => PaymentResultScreen.show(context, kind: PaymentResultKind.success),
          child: const Text('open'),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    expect(find.text('Payment successful'), findsOneWidget);
    await t.tap(find.text('Done'));
    await t.pumpAndSettle();
    expect(find.text('Payment successful'), findsNothing);
  });
}
