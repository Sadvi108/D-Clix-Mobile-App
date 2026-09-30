import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/autopay.dart';
import '../services/response_utils.dart';
import '../theme/app_icons.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/gradient_button.dart';
import '../widgets/premium_kit.dart';
import '../widgets/rn_kit.dart';
import 'payment/bcpg_webview_screen.dart';

/// Auto Pay — save a debit or credit card on Boost once, and pending invoices are paid
/// from it.
///
/// Switching it on hands over to Boost's save-card page. The app never sees the card
/// number. See [AutoPay] for the server contract.
class AutoPayScreen extends StatefulWidget {
  /// Where the mandate comes from. A seam so tests can show every state.
  final Future<AutoPayMandate> Function() load;
  const AutoPayScreen({super.key, this.load = AutoPay.status});

  @override
  State<AutoPayScreen> createState() => _AutoPayScreenState();
}

class _AutoPayScreenState extends State<AutoPayScreen> {
  AutoPayMandate _m = AutoPayMandate.off;
  bool _loading = true;
  String? _error;
  bool _busy = false;

  bool get _on => _m.state != AutoPayState.off;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var m = AutoPayMandate.off;
    String? error;
    try {
      m = await widget.load();
    } catch (e) {
      error = friendlyError(e);
    }
    if (!mounted) return;
    setState(() {
      _m = m;
      _error = error;
      _loading = false;
    });
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Save a card, or replace the saved one. Both go through Boost's page.
  Future<void> _link() async {
    final before = _m;
    setState(() => _busy = true);
    try {
      final start = await AutoPay.setup();
      if (!mounted) return;
      final result = await BcpgWebViewScreen.open(context,
          paymentUrl: start.url, referenceId: start.referenceId ?? '');
      final declined = result?['status'] == 'failed';
      // The redirect only brings the browser back. The server says whether it worked, and
      // Boost's webhook can land a moment after the member does.
      for (var i = 0; i < 3; i++) {
        if (i > 0) await Future<void>.delayed(const Duration(seconds: 2));
        await _load();
        if (!mounted || _m.state != AutoPayState.pending) break;
      }
      if (_m.state == before.state && _m.label == before.label) {
        _toast(declined
            ? 'Your card could not be saved. Please try again or use another card.'
            : before.state == AutoPayState.off
                ? 'Auto Pay was not set up.'
                : 'Your card was not changed.');
      } else {
        _toast(switch (_m.state) {
          AutoPayState.active => 'Auto Pay is on — paying from ${_m.label}.',
          AutoPayState.pending => 'Almost done — Boost is still confirming your card.',
          AutoPayState.failed => _m.reason ?? 'Your card could not be saved.',
          AutoPayState.off => 'Auto Pay was not set up.',
        });
      }
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff() async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Remove your card?'),
        content: Text(
            'Auto Pay will turn off and ${_m.label} will be removed. You will pay your '
            'fees yourself from Fees Due.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: c.danger),
              child: const Text('Yes, remove')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await AutoPay.cancel();
      await _load();
      _toast('Card removed. Auto Pay is off.');
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(children: [
        const RnHeader(title: 'Auto Pay'),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Padding(
                      padding: const EdgeInsets.all(Gaps.xl),
                      child: ErrorState(
                          message: _error,
                          onRetry: () {
                            setState(() => _loading = true);
                            _load();
                          }),
                    )
                  : _content(c),
        ),
      ]),
    );
  }

  Widget _content(AppColors c) {
    final cardNote = switch (_m.state) {
      AutoPayState.failed => 'Needs updating',
      AutoPayState.pending => 'Being confirmed by Boost',
      _ when _m.expiry != null => 'Expires ${_m.expiry}',
      _ => 'Debit or credit card',
    };
    return ListView(
      padding: EdgeInsets.only(
          top: Gaps.sm, bottom: Gaps.xxxl + MediaQuery.paddingOf(context).bottom),
      children: [
        _hero(c),
        const SizedBox(height: Gaps.lg),
        GroupCard(children: [
          MergeSemantics(
            child: PremiumRow(
              icon: Ion.repeat,
              title: 'Auto Pay',
              subtitle: switch (_m.state) {
                AutoPayState.off => 'Off — you pay by hand',
                AutoPayState.pending => 'On — confirming your card',
                AutoPayState.active => 'On — paying your invoices',
                AutoPayState.failed => 'On — needs your attention',
              },
              trailing: Switch.adaptive(
                value: _on,
                onChanged: _busy ? null : (v) => v ? _link() : _turnOff(),
                activeTrackColor: c.primary,
              ),
            ),
          ),
        ]),
        if (!_on) ...[
          const SectionLabel('How it works'),
          const GroupCard(children: [
            PremiumRow(
              icon: Ion.cardOutline,
              tint: PremiumTint.indigo,
              title: 'Save your card',
              subtitle: 'Debit or credit, on Boost\'s secure page',
            ),
            PremiumRow(
              icon: Ion.shieldCheckmarkOutline,
              tint: PremiumTint.green,
              title: 'Quick card check',
              subtitle: 'A RM 1.00 hold that is voided, not charged',
            ),
            PremiumRow(
              icon: Ion.calendarOutline,
              tint: PremiumTint.amber,
              title: 'Invoices paid for you',
              subtitle: 'Receipts appear in Payment History',
            ),
          ]),
        ] else ...[
          const SectionLabel('Card'),
          GroupCard(children: [
            PremiumRow(
              icon: Ion.cardOutline,
              tint: PremiumTint.indigo,
              title: _m.label,
              subtitle: cardNote,
              onTap: _busy ? null : _link,
            ),
          ]),
          const SectionLabel('Schedule'),
          GroupCard(children: [
            PremiumRow(
              icon: Ion.calendarOutline,
              tint: PremiumTint.amber,
              title: 'Next payment',
              subtitle: _m.nextCharge != null
                  ? DateFormat('d MMM yyyy').format(_m.nextCharge!)
                  : 'When your next invoice is due',
            ),
            const PremiumRow(
              icon: Ion.receiptOutline,
              tint: PremiumTint.sky,
              title: 'Receipts',
              subtitle: 'Every payment appears in Payment History',
            ),
          ]),
          if (_m.state == AutoPayState.failed) ...[
            const SizedBox(height: Gaps.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.xl),
              child: GradientButton(
                label: 'Update card',
                trailingIcon: AppIcons.arrow_forward,
                loading: _busy,
                onPressed: _busy ? null : _link,
              ),
            ),
          ],
        ],
        const SizedBox(height: Gaps.xl),
        _secureNote(c),
      ],
    );
  }

  /// Dark slate card that says, before anything else, what state Auto Pay is in.
  Widget _hero(AppColors c) {
    final (pill, tone, title, body) = switch (_m.state) {
      AutoPayState.off => (
          'OFF',
          const Color(0xFFCBD5E1),
          'Never miss a monthly fee',
          'Save a debit or credit card once and your invoices are paid on time, '
              'every month.'
        ),
      AutoPayState.pending => (
          'PENDING',
          c.warning,
          'Almost there',
          'Boost is confirming your card. Nothing is charged until it is confirmed.'
        ),
      AutoPayState.active => (
          'ON',
          c.success,
          'Auto Pay is on',
          '${_m.label} is paying your invoices.'
        ),
      AutoPayState.failed => (
          'ACTION NEEDED',
          c.danger,
          'Payment didn\'t go through',
          _m.reason ??
              'Update your card to keep Auto Pay running.'
        ),
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: Gaps.xl),
      clipBehavior: Clip.antiAlias,
      decoration: premiumSlate(c),
      child: Stack(children: [
        const SlateGlow(),
        Padding(
          padding: const EdgeInsets.all(Gaps.xl),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                    color: Color(0x1FFFFFFF), shape: BoxShape.circle),
                child: const Icon(Ion.repeat, size: 22, color: Colors.white),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: tone.withValues(alpha: 0.4)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration:
                          BoxDecoration(color: tone, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  Text(pill,
                      style: TextStyle(
                          color: tone,
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8)),
                ]),
              ),
            ]),
            const SizedBox(height: Gaps.lg),
            Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Text(body,
                style: const TextStyle(
                    color: Color(0xCCFFFFFF), fontSize: 13.5, height: 1.45)),
          ]),
        ),
      ]),
    );
  }

  Widget _secureNote(AppColors c) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gaps.xl + 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Ion.lockClosed, size: 14, color: c.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
                'Secured by Boost. D-CLIX never sees your card number.',
                style: TextStyle(fontSize: 12, height: 1.4, color: c.textMuted)),
          ),
        ]),
      );
}
