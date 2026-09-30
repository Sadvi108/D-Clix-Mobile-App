import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// Off: one switch. Turning it on asks the monthly amount (and shows a parent that the
/// whole family is covered), then hands over to Boost's save-card page. The app never sees
/// the card number. On: Pause / Resume and Disable replace the switch, because those are
/// three states of one lifecycle, not an on/off setting. See [AutoPay] for the contract.
class AutoPayScreen extends StatefulWidget {
  /// Where the mandate comes from. A seam so tests can show every state.
  final Future<AutoPayMandate> Function() load;

  /// Who Auto Pay covers. A seam for the same reason.
  final Future<AutoPayFamily> Function() family;

  const AutoPayScreen(
      {super.key, this.load = AutoPay.status, this.family = AutoPay.family});

  @override
  State<AutoPayScreen> createState() => _AutoPayScreenState();
}

class _AutoPayScreenState extends State<AutoPayScreen> {
  AutoPayMandate _m = AutoPayMandate.off;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  late final Future<AutoPayFamily> _familyFuture;
  AutoPayFamily _family = const [];

  bool get _on => _m.state != AutoPayState.off;

  @override
  void initState() {
    super.initState();
    _familyFuture = widget.family();
    _familyFuture.then((f) {
      if (mounted) setState(() => _family = f);
    });
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

  /// Run one server action with the controls locked, then show what the server now says.
  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      await _load();
      _toast(done);
    } catch (e) {
      _toast(friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The switch was turned on: amount (and family) first, then Boost. The sheet opens at
  /// once; the family list fills in when the sibling lookup lands.
  Future<void> _start() async {
    final amount = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.appColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xxl))),
      builder: (_) => _SetupSheet(family: _familyFuture),
    );
    if (amount == null || !mounted) return;
    await _link(monthlyAmount: amount, family: await _familyFuture);
  }

  /// A new card for the same plan: keep the amount and family, only the card changes.
  Future<void> _changeCard() async =>
      _link(monthlyAmount: _m.monthlyAmount, family: await _familyFuture);

  /// Save a card, or replace the saved one. Both go through Boost's page.
  Future<void> _link({double? monthlyAmount, AutoPayFamily family = const []}) async {
    final before = _m;
    setState(() => _busy = true);
    try {
      final start = await AutoPay.setup(
          monthlyAmount: monthlyAmount,
          studentIds: [for (final m in family) m.id]);
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
          AutoPayState.paused => 'Card saved. Auto Pay is paused.',
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

  Future<bool> _confirm(
      {required String title,
      required String body,
      required String yes,
      bool destructive = false}) async {
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: destructive
                  ? TextButton.styleFrom(foregroundColor: c.danger)
                  : null,
              child: Text(yes)),
        ],
      ),
    );
    return ok == true && mounted;
  }

  Future<void> _pause() async {
    if (await _confirm(
        title: 'Pause Auto Pay?',
        body: 'Your card stays saved, but no payments are taken until you resume. '
            'Pay anything that falls due in the meantime from Fees Due.',
        yes: 'Yes, pause')) {
      await _run(AutoPay.pause, 'Auto Pay paused. Your card stays saved.');
    }
  }

  Future<void> _resume() => _run(AutoPay.resume, 'Auto Pay resumed.');

  Future<void> _disable() async {
    if (await _confirm(
        title: 'Remove your card?',
        body: 'Auto Pay will turn off and ${_m.label} will be removed. You will pay your '
            'fees yourself from Fees Due.',
        yes: 'Yes, remove',
        destructive: true)) {
      await _run(AutoPay.cancel, 'Card removed. Auto Pay is off.');
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
                AutoPayState.paused => 'Paused — no payments until you resume',
                AutoPayState.failed => 'On — needs your attention',
              },
              trailing: _on
                  ? null
                  : Switch.adaptive(
                      value: false,
                      onChanged: _busy ? null : (v) => v ? _start() : null,
                      activeTrackColor: c.primary,
                    ),
            ),
          ),
        ]),
        if (_on) _manage(c),
        if (!_on) ...[
          const SectionLabel('How it works'),
          const GroupCard(children: [
            PremiumRow(
              icon: Ion.walletOutline,
              tint: PremiumTint.green,
              title: 'Set your monthly amount',
              subtitle: 'Family accounts are covered together',
            ),
            PremiumRow(
              icon: Ion.cardOutline,
              tint: PremiumTint.indigo,
              title: 'Save your card',
              subtitle: 'Debit or credit, on Boost\'s secure page',
            ),
            PremiumRow(
              icon: Ion.calendarOutline,
              tint: PremiumTint.amber,
              title: 'Invoices paid for you',
              subtitle: 'Pause or turn it off at any time',
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
              onTap: _busy ? null : _changeCard,
            ),
          ]),
          const SectionLabel('Details'),
          GroupCard(children: [
            if (_m.monthlyAmount != null)
              PremiumRow(
                icon: Ion.walletOutline,
                tint: PremiumTint.green,
                title: 'Monthly amount',
                subtitle: 'RM ${_m.monthlyAmount!.toStringAsFixed(2)}',
              ),
            if (_family.length > 1)
              PremiumRow(
                icon: Ion.peopleOutline,
                tint: PremiumTint.violet,
                title: 'Covers',
                subtitle: _family.map((m) => m.name).join(', '),
              ),
            PremiumRow(
              icon: Ion.calendarOutline,
              tint: PremiumTint.amber,
              title: 'Next payment',
              subtitle: _m.state == AutoPayState.paused
                  ? 'None while paused'
                  : _m.nextCharge != null
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
                onPressed: _busy ? null : _changeCard,
              ),
            ),
          ],
        ],
        const SizedBox(height: Gaps.xl),
        _secureNote(c),
      ],
    );
  }

  /// Pause ↔ Resume share one slot (only one is ever possible); Disable stands apart in red.
  Widget _manage(AppColors c) {
    final hold = switch (_m.state) {
      AutoPayState.active =>
        _ActionButton(label: 'Pause', icon: Ion.pause, onTap: _busy ? null : _pause),
      AutoPayState.paused => _ActionButton(
          label: 'Resume',
          icon: Ion.play,
          filled: true,
          onTap: _busy ? null : _resume),
      _ => null,
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.md, Gaps.xl, 0),
      child: Row(children: [
        if (hold != null) ...[Expanded(child: hold), const SizedBox(width: Gaps.md)],
        Expanded(
          child: _ActionButton(
              label: 'Disable',
              icon: Ion.powerOutline,
              danger: true,
              onTap: _busy ? null : _disable),
        ),
      ]),
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
      AutoPayState.paused => (
          'PAUSED',
          c.warning,
          'Auto Pay is paused',
          '${_m.label} stays saved. No payments are taken until you resume.'
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
                child: Icon(
                    _m.state == AutoPayState.paused ? Ion.pause : Ion.repeat,
                    size: 22,
                    color: Colors.white),
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

/// A 52 pt action: outlined by default, brand-filled for the one action a paused member
/// needs, red-outlined for the destructive one.
class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool filled;
  final bool danger;
  const _ActionButton(
      {required this.label,
      required this.icon,
      required this.onTap,
      this.filled = false,
      this.danger = false});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final fg = filled ? Colors.white : (danger ? c.danger : c.textPrimary);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      excludeSemantics: true,
      child: Opacity(
        opacity: onTap == null ? 0.5 : 1,
        child: Material(
          color: filled ? c.primary : c.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Radii.lg),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.lg),
                border: filled
                    ? null
                    : Border.all(
                        color: danger ? c.danger.withValues(alpha: 0.45) : c.border),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(icon, size: 18, color: fg),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        color: fg, fontSize: 15, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small window after the switch goes on: how much to take each month, and — for a
/// family — who it covers. Everyone is covered; there is no per-member opt-out, so the
/// list is read-only on purpose.
class _SetupSheet extends StatefulWidget {
  final Future<AutoPayFamily> family;
  const _SetupSheet({required this.family});

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  final _amount = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _continue() {
    final v = double.tryParse(_amount.text.trim());
    if (v == null || v <= 0) {
      setState(() => _error = 'Enter the amount to take each month.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    const labelPad = EdgeInsets.fromLTRB(Gaps.xl + 4, Gaps.lg, Gaps.xl + 4, 8);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: Gaps.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.xl + 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Set up Auto Pay',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: c.textPrimary)),
                const SizedBox(height: 4),
                Text('Then add your card on Boost\'s secure page.',
                    style: TextStyle(fontSize: 13, color: c.textSecondary)),
              ]),
            ),
            const SectionLabel('Monthly amount', padding: labelPad),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.xl),
              child: TextField(
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textInputAction: TextInputAction.done,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d{0,6}(\.\d{0,2})?')),
                ],
                style: TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary),
                decoration: InputDecoration(
                  // prefixIcon, not prefixText: prefixText hides until the field has focus
                  // or text, leaving a bare "0.00" with no currency.
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 16, right: 6),
                    child: Text('RM',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: c.textSecondary)),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                  hintText: '0.00',
                  helperText: 'Taken from your card each month.',
                  errorText: _error,
                  filled: true,
                  fillColor: c.surface,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg)),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _continue(),
              ),
            ),
            FutureBuilder<AutoPayFamily>(
              future: widget.family,
              builder: (context, snap) {
                final family = snap.data ?? const [];
                if (family.length < 2) return const SizedBox.shrink();
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const SectionLabel('Family members covered', padding: labelPad),
                  GroupCard(children: [
                    for (final m in family)
                      PremiumRow(
                        icon: Ion.personOutline,
                        tint: PremiumTint.violet,
                        title: m.name,
                        trailing: Icon(Ion.checkmarkCircle, size: 22, color: c.success),
                      ),
                  ]),
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(Gaps.xl + 4, Gaps.sm, Gaps.xl + 4, 0),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Ion.informationCircleOutline, size: 15, color: c.textMuted),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            'Auto Pay covers everyone in your family. One member cannot '
                            'be left out.',
                            style: TextStyle(
                                fontSize: 12, height: 1.4, color: c.textMuted)),
                      ),
                    ]),
                  ),
                ]);
              },
            ),
            const SizedBox(height: Gaps.xl),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.xl),
              child: GradientButton(
                label: 'Continue to Boost',
                trailingIcon: AppIcons.arrow_forward,
                onPressed: _continue,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
