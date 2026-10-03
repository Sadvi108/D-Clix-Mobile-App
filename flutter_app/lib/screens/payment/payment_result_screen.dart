import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../services/boost_payment.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_theme.dart';
import '../../theme/ion.dart';
import '../../widgets/gradient_button.dart';
import '../../widgets/premium_kit.dart';

enum PaymentResultKind { success, failed, cancelled, pending }

/// What to tell the member once Boost's page closes. [gatewayStatus] is what the WebView
/// popped: "success" or "failed" from /Payment/Completed/{Success|Failed}, "cancelled" when
/// the member cancelled before paying, "closed" when they closed the page after reaching the
/// bank, null when the return carried no status.
///
/// When Boost said success but the server still lists the invoices as due, the answer is
/// "processing", never "failed": that member has paid and must not be told to pay again.
PaymentResultKind paymentResultKind(PaymentResult verdict, String? gatewayStatus) {
  if (verdict.outcome == PaymentOutcome.paid) return PaymentResultKind.success;
  // Closed after reaching the bank: FPX can still settle it, so never "failed" or "cancelled".
  if (gatewayStatus == 'success' || gatewayStatus == 'closed') return PaymentResultKind.pending;
  if (gatewayStatus == 'failed') return PaymentResultKind.failed;
  if (verdict.outcome == PaymentOutcome.unpaid) {
    return gatewayStatus == 'cancelled' ? PaymentResultKind.cancelled : PaymentResultKind.failed;
  }
  return PaymentResultKind.pending;
}

/// Full-screen outcome after an online payment: paid, not paid, or still being confirmed.
class PaymentResultScreen extends StatelessWidget {
  final PaymentResultKind kind;
  final double? amount;

  /// "2 invoices", "3 items".
  final String? paidFor;
  final String? reference;
  final DateTime at;

  PaymentResultScreen({
    super.key,
    required this.kind,
    this.amount,
    this.paidFor,
    this.reference,
    DateTime? at,
  }) : at = at ?? DateTime.now();

  static Future<void> show(BuildContext context,
          {required PaymentResultKind kind, double? amount, String? paidFor, String? reference}) =>
      Navigator.of(context, rootNavigator: true).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => PaymentResultScreen(
            kind: kind, amount: amount, paidFor: paidFor, reference: reference),
      ));

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final (icon, tint, title, body, button) = switch (kind) {
      PaymentResultKind.success => (
          Ion.checkmarkCircle,
          c.success,
          'Payment successful',
          'Thank you. Your payment has been received.',
          'Done',
        ),
      PaymentResultKind.failed => (
          Ion.closeCircle,
          c.danger,
          'Payment failed',
          'The payment did not go through. Your invoices are still due, and you can try again.',
          'Try again',
        ),
      PaymentResultKind.cancelled => (
          Ion.closeCircle,
          c.danger,
          'Payment cancelled',
          'You left the payment page before paying. Your invoices are still due.',
          'Try again',
        ),
      PaymentResultKind.pending => (
          Ion.hourglassOutline,
          c.warning,
          'Payment processing',
          'Your bank has not confirmed this payment yet. Your invoices update once it does. '
              'Check Payment History before paying again.',
          'Done',
        ),
    };
    final lines = [
      if (amount != null) ('Amount', 'RM ${amount!.toStringAsFixed(2)}'),
      if (paidFor != null) ('For', paidFor!),
      if (reference != null && reference!.isNotEmpty) ('Reference', reference!),
      ('Date', DateFormat('d MMM yyyy, h:mm a').format(at)),
    ];
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Gaps.xl, 56, Gaps.xl, Gaps.xl),
              children: [
                Center(
                  child: Container(
                    width: 104,
                    height: 104,
                    decoration: BoxDecoration(color: tint.withValues(alpha: 0.12), shape: BoxShape.circle),
                    child: Icon(icon, size: 64, color: tint),
                  ),
                ),
                const SizedBox(height: Gaps.xl),
                Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: c.textPrimary)),
                const SizedBox(height: 10),
                Text(body,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14.5, height: 1.45, color: c.textSecondary)),
                const SizedBox(height: Gaps.xl),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  decoration: premiumCard(c),
                  child: Column(children: [
                    for (final (label, value) in lines)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(label, style: TextStyle(fontSize: 13.5, color: c.textSecondary)),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(value,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                    fontSize: 14, fontWeight: FontWeight.w700, color: c.textPrimary)),
                          ),
                        ]),
                      ),
                  ]),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.md, Gaps.xl, Gaps.lg),
            child: GradientButton(
              label: button,
              trailingIcon: kind == PaymentResultKind.success ? AppIcons.check : null,
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
        ]),
      ),
    );
  }
}
