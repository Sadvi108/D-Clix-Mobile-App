import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
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
/// Off: one switch. Turning it on asks which of the club's invoice types to pay and a limit
/// per invoice (and shows a parent that the whole family is covered), then the member agrees
/// to the recurring billing terms, then Boost's save-card page takes over. The app never
/// sees the card number. On: Pause / Resume and Disable replace the switch, because those
/// are three states of one lifecycle, not an on/off setting. See [AutoPay] for the contract.
class AutoPayScreen extends StatefulWidget {
  /// Where the mandate comes from. A seam so tests can show every state.
  final Future<AutoPayMandate> Function() load;

  /// Who Auto Pay covers. A seam for the same reason.
  final Future<AutoPayFamily> Function() family;

  /// The invoice types the member may tick: the club's own list, or every type the academy
  /// lists when the club sent none. A seam so tests need no signed-in session.
  final Future<List<String>> Function() clubTypes;

  const AutoPayScreen(
      {super.key,
      this.load = AutoPay.status,
      this.family = AutoPay.family,
      this.clubTypes = AutoPay.invoiceTypeChoices});

  @override
  State<AutoPayScreen> createState() => _AutoPayScreenState();
}

/// What the member set up: the invoice types to pay (null when the club sent none, so the
/// server decides) and the most Auto Pay pays for one invoice.
typedef _Plan = ({List<String>? invoiceTypes, double? perChargeCap});

class _AutoPayScreenState extends State<AutoPayScreen> {
  AutoPayMandate _m = AutoPayMandate.off;
  bool _loading = true;
  String? _error;
  bool _busy = false;
  late final Future<AutoPayFamily> _familyFuture;
  AutoPayFamily _family = const [];
  late final Future<List<String>> _typesFuture;

  bool get _on => _m.state != AutoPayState.off;

  @override
  void initState() {
    super.initState();
    _familyFuture = widget.family();
    // Asked for now, so the setup sheet rarely has to wait for it.
    _typesFuture = widget.clubTypes();
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

  /// The switch was turned on: what to pay (and family) first, then the agreement, then
  /// Boost. The sheet opens at once; the family list fills in when the sibling lookup lands.
  Future<void> _start() async {
    final plan = await showModalBottomSheet<_Plan>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.appColors.background,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xxl))),
      builder: (_) => _SetupSheet(family: _familyFuture, types: _typesFuture),
    );
    if (plan == null || !mounted) return;
    await _agreeThenLink(plan);
  }

  /// A new card for the same plan: only the card changes. The member agrees again, because
  /// the cardholder declaration is about the card.
  Future<void> _changeCard() => _agreeThenLink((
        invoiceTypes: _m.invoiceTypes.isEmpty ? null : _m.invoiceTypes,
        perChargeCap: _m.perChargeCap,
      ));

  /// The last step before Boost: the member reviews the plan and agrees to the recurring
  /// billing terms. Backing out enables nothing.
  Future<void> _agreeThenLink(_Plan plan) async {
    final family = await _familyFuture;
    if (!mounted) return;
    final agreed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => _ConsentPage(plan: plan, family: family)));
    if (agreed == true && mounted) await _link(plan);
  }

  /// Save a card, or replace the saved one. Both go through Boost's page.
  Future<void> _link(_Plan plan) async {
    final before = _m;
    setState(() => _busy = true);
    try {
      final start = await AutoPay.setup(
          invoiceTypes: plan.invoiceTypes,
          perChargeCap: plan.perChargeCap,
          consentVersion: kAutoPayTermsVersion);
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
              title: 'Choose what it pays',
              subtitle: 'Invoice types and a limit per invoice',
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
            if (_m.invoiceTypes.isNotEmpty)
              PremiumRow(
                icon: Ion.documentTextOutline,
                tint: PremiumTint.teal,
                title: 'Pays',
                subtitle: _m.invoiceTypes.join(', '),
              ),
            if (_m.perChargeCap != null)
              PremiumRow(
                icon: Ion.walletOutline,
                tint: PremiumTint.green,
                title: 'Limit per invoice',
                subtitle: 'RM ${_m.perChargeCap!.toStringAsFixed(2)}',
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
        // Manual payment never depends on Auto Pay: on, paused or off, any invoice can be paid
        // through the gateway now, and Auto Pay leaves a paid invoice alone.
        const SectionLabel('Good to know'),
        GroupCard(children: [
          PremiumRow(
            icon: Ion.cashOutline,
            tint: PremiumTint.green,
            title: 'Pay yourself any time',
            subtitle: _on
                ? 'Auto Pay skips invoices you have paid'
                : 'Pay any invoice from Pay Your Dues',
            onTap: () => context.push('/invoices'),
          ),
          PremiumRow(
            icon: Ion.documentTextOutline,
            tint: PremiumTint.slate,
            title: 'Recurring Billing Terms',
            subtitle: 'And Cancellation Policy',
            onTap: () => showAutoPayTerms(context),
          ),
        ]),
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
          'Save a debit or credit card once and the invoices you choose are paid as '
              'they fall due.'
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

/// The small window after the switch goes on: the most Auto Pay pays for one invoice, which
/// invoice types to pay, and — for a family — who it covers. Everyone is covered;
/// there is no per-member opt-out, so the family list is read-only on purpose.
class _SetupSheet extends StatefulWidget {
  final Future<AutoPayFamily> family;

  /// The invoice types on offer. Empty: there is nothing to choose, and the server decides.
  final Future<List<String>> types;
  const _SetupSheet({required this.family, required this.types});

  @override
  State<_SetupSheet> createState() => _SetupSheetState();
}

class _SetupSheetState extends State<_SetupSheet> {
  final _amount = TextEditingController();
  // Null until the types arrive; Continue waits for them.
  List<String>? _types;
  // All ticked to start: the member leaves out what they would rather pay by hand.
  final _picked = <String>{};
  String? _error;
  String? _typesError;

  @override
  void initState() {
    super.initState();
    widget.types.then((t) {
      if (mounted) setState(() => _picked.addAll(_types = t));
    }, onError: (_) {
      if (mounted) setState(() => _types = const []);
    });
  }

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  void _toggle(String type) => setState(() {
        if (!_picked.remove(type)) _picked.add(type);
        if (_picked.isNotEmpty) _typesError = null;
      });

  void _continue() {
    final types = _types ?? const <String>[];
    final cap = double.tryParse(_amount.text.trim());
    final noCap = cap == null || cap <= 0;
    final noTypes = types.isNotEmpty && _picked.isEmpty;
    setState(() {
      _error = noCap ? 'Enter your limit per invoice.' : null;
      _typesError = noTypes ? 'Choose at least one type of invoice.' : null;
    });
    if (noCap || noTypes) return;
    Navigator.pop<_Plan>(context, (
      // In the club's order, not the order they were ticked in.
      invoiceTypes: types.isEmpty ? null : types.where(_picked.contains).toList(),
      perChargeCap: cap,
    ));
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
                Text('Then agree to the terms and add your card on Boost\'s secure page.',
                    style: TextStyle(fontSize: 13, color: c.textSecondary)),
              ]),
            ),
            const SectionLabel('Limit per invoice', padding: labelPad),
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
                  helperText: 'Invoices above this amount are left for you to pay.',
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
            if (_types == null) ...[
              const SectionLabel('Invoices to pay', padding: labelPad),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.xl + 4),
                child: Row(children: [
                  SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: c.textMuted)),
                  const SizedBox(width: 10),
                  Text('Loading your academy\'s invoice types…',
                      style: TextStyle(fontSize: 12.5, color: c.textMuted)),
                ]),
              ),
            ] else if (_types!.isNotEmpty) ...[
              const SectionLabel('Invoices to pay', padding: labelPad),
              GroupCard(children: [
                for (final t in _types!)
                  _CheckRow(title: t, checked: _picked.contains(t), onTap: () => _toggle(t)),
              ]),
              if (_typesError != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(Gaps.xl + 4, Gaps.sm, Gaps.xl + 4, 0),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(_typesError!,
                        style: TextStyle(fontSize: 12, height: 1.4, color: c.danger)),
                  ),
                ),
            ],
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
                label: 'Continue',
                trailingIcon: AppIcons.arrow_forward,
                onPressed: _types == null ? null : _continue,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// A row that ticks on and off. The whole row is the target, and a screen reader hears one
/// checkbox named by the title.
class _CheckRow extends StatelessWidget {
  final String title;
  final bool checked;
  final VoidCallback onTap;
  const _CheckRow({required this.title, required this.checked, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    return Semantics(
      checked: checked,
      label: title,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: PremiumRow(
            icon: Ion.documentTextOutline,
            tint: PremiumTint.teal,
            title: title,
            trailing: Icon(checked ? Ion.checkbox : Ion.squareOutline,
                size: 24, color: checked ? c.primary : c.textMuted),
          ),
        ),
      ),
    );
  }
}

/// Which text of the recurring billing terms a member agreed to. Enable sends it so the
/// server records it: change it whenever [_terms] changes.
const kAutoPayTermsVersion = 'recurring-terms-2026-10-02.2';

/// The Recurring Billing Terms and Cancellation Policy, in plain words. Only what the app
/// and the club actually do: no refund timelines or fees the club has not stated.
const _terms = [
  (
    'What gets charged',
    'Only invoices of the types you chose, for everyone Auto Pay covers, and only an invoice '
        'of your limit per invoice or less. Anything Auto Pay does not pay stays in Fees Due.'
  ),
  (
    'When you are charged',
    'As those invoices fall due. Each payment is taken from the card you saved on Boost\'s '
        'secure page.'
  ),
  (
    'Checking your card',
    'When you save your card, Boost checks it with a RM 1.00 hold that is voided, not '
        'charged.'
  ),
  ('Receipts', 'Every payment appears in Payment History.'),
  (
    'Paying yourself',
    'You can pay any invoice yourself from Fees Due at any time, whether Auto Pay is on, '
        'paused or off. An invoice you have paid is marked paid, and Auto Pay does not charge '
        'it again.'
  ),
  (
    'Pausing and resuming',
    'Tap Pause on the Auto Pay screen to stop payments for a while. Your card stays saved '
        'and nothing is taken until you tap Resume. Pay anything that falls due in the '
        'meantime from Fees Due.'
  ),
  (
    'Cancelling',
    'Tap Disable on the Auto Pay screen. Auto Pay turns off and your card is removed. A '
        'payment that has already started may still complete.'
  ),
  (
    'If a payment fails',
    'Auto Pay shows Action needed and the invoice stays in Fees Due. Update your card on '
        'the Auto Pay screen, or pay the invoice from Fees Due.'
  ),
  (
    'Questions about a charge',
    'Contact your academy about any charge you do not recognise or think is wrong.'
  ),
];

const _kPolicy = 'Recurring Billing Terms and Cancellation Policy';

/// The terms in a sheet, from the agreement and from the Auto Pay screen alike.
void showAutoPayTerms(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: context.appColors.background,
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xxl))),
      builder: (context) {
        final c = context.appColors;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Gaps.xl + 4, 0, Gaps.xl + 4, Gaps.xl),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Semantics(
                header: true,
                child: Text(_kPolicy,
                    style: TextStyle(
                        fontSize: 20, fontWeight: FontWeight.w800, color: c.textPrimary)),
              ),
              for (final (heading, body) in _terms) ...[
                const SizedBox(height: Gaps.lg),
                Semantics(
                  header: true,
                  child: Text(heading,
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: c.textPrimary)),
                ),
                const SizedBox(height: 4),
                Text(body,
                    style: TextStyle(fontSize: 13.5, height: 1.45, color: c.textSecondary)),
              ],
            ]),
          ),
        );
      },
    );

/// The last step before Boost: what Auto Pay will do, and the member's agreement to the
/// recurring billing terms. Pops true only once the box is ticked and Agree is tapped;
/// Back pops false and nothing is enabled.
class _ConsentPage extends StatefulWidget {
  final _Plan plan;
  final AutoPayFamily family;
  const _ConsentPage({required this.plan, required this.family});

  @override
  State<_ConsentPage> createState() => _ConsentPageState();
}

class _ConsentPageState extends State<_ConsentPage> {
  static const _lead =
      'I am the cardholder or an authorised account user, and I agree to the ';
  static const _policy = _kPolicy;

  bool _agreed = false;
  late final _policyLink = TapGestureRecognizer()..onTap = _showTerms;

  @override
  void dispose() {
    _policyLink.dispose();
    super.dispose();
  }

  void _toggle() => setState(() => _agreed = !_agreed);

  void _showTerms() => showAutoPayTerms(context);

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final types = widget.plan.invoiceTypes ?? const [];
    final cap = widget.plan.perChargeCap;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(children: [
        RnHeader(title: 'Review and agree', onBack: () => Navigator.pop(context, false)),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Gaps.lg),
            children: [
              const SectionLabel('Your Auto Pay',
                  padding: EdgeInsets.fromLTRB(Gaps.xl + 4, Gaps.sm, Gaps.xl + 4, 10)),
              GroupCard(children: [
                PremiumRow(
                  icon: Ion.documentTextOutline,
                  tint: PremiumTint.teal,
                  titleLines: 3,
                  title:
                      'Pays: ${types.isEmpty ? 'invoices from your academy' : types.join(', ')}',
                ),
                if (cap != null)
                  PremiumRow(
                    icon: Ion.walletOutline,
                    tint: PremiumTint.green,
                    titleLines: 3,
                    title: 'Up to RM ${cap.toStringAsFixed(2)} per invoice',
                  ),
                if (widget.family.length > 1)
                  PremiumRow(
                    icon: Ion.peopleOutline,
                    tint: PremiumTint.violet,
                    titleLines: 3,
                    title: 'Covers: ${widget.family.map((m) => m.name).join(', ')}',
                  ),
                const PremiumRow(
                  icon: Ion.cardOutline,
                  tint: PremiumTint.indigo,
                  titleLines: 3,
                  title: 'Card: saved on Boost\'s secure page',
                  subtitle: 'D-CLIX never sees your card number',
                ),
                const PremiumRow(
                  icon: Ion.powerOutline,
                  tint: PremiumTint.slate,
                  titleLines: 3,
                  title: 'Turn it off any time: Auto Pay → Disable',
                ),
              ]),
            ],
          ),
        ),
        // Pinned, so the agreement and its button never scroll apart.
        Container(
          padding: EdgeInsets.fromLTRB(
              Gaps.xl, Gaps.md, Gaps.xl, Gaps.lg + MediaQuery.paddingOf(context).bottom),
          decoration: BoxDecoration(
              color: c.background, border: Border(top: BorderSide(color: c.borderLight))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _agreement(c),
            const SizedBox(height: Gaps.md),
            GradientButton(
              label: 'Agree and continue to Boost',
              trailingIcon: AppIcons.arrow_forward,
              onPressed: _agreed ? () => Navigator.pop(context, true) : null,
            ),
          ]),
        ),
      ]),
    );
  }

  /// The whole row ticks the box, except the policy, which opens the terms instead. One
  /// checkbox to a screen reader, with the terms as its custom action.
  Widget _agreement(AppColors c) => Semantics(
        checked: _agreed,
        label: '$_lead$_policy.',
        onTap: _toggle,
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Read the $_policy'): _showTerms
        },
        excludeSemantics: true,
        child: Material(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          child: InkWell(
            onTap: _toggle,
            borderRadius: BorderRadius.circular(Radii.lg),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.lg),
                border: Border.all(color: _agreed ? c.primary : c.border),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(_agreed ? Ion.checkbox : Ion.squareOutline,
                    size: 24, color: _agreed ? c.primary : c.textMuted),
                const SizedBox(width: Gaps.md),
                Expanded(
                  child: Text.rich(TextSpan(
                    style: TextStyle(fontSize: 13.5, height: 1.45, color: c.textPrimary),
                    children: [
                      const TextSpan(text: _lead),
                      TextSpan(
                        text: _policy,
                        recognizer: _policyLink,
                        style: TextStyle(
                            color: c.primary,
                            fontWeight: FontWeight.w700,
                            decoration: TextDecoration.underline,
                            decorationColor: c.primary),
                      ),
                      const TextSpan(text: '.'),
                    ],
                  )),
                ),
              ]),
            ),
          ),
        ),
      );
}
