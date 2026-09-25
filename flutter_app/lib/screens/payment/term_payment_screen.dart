import '../../theme/app_icons.dart';
import 'package:flutter/material.dart';

import '../../services/boost_payment.dart';
import 'bcpg_webview_screen.dart';
import '../../services/api.dart';
import '../../services/prepay_service.dart';
import '../../services/response_utils.dart';
import '../../services/user_session.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_header.dart';

/// A payable person (the logged-in account and its siblings/children).
class _Payee {
  final int id;
  final String name;
  const _Payee(this.id, this.name);
}

/// Term / advance payment: pick a year, the months to pay, and which
/// students (self + siblings) to pay for. Each resulting invoice is listed in
/// detail, then totalled. Mirrors the club's classic "Term Payment" screen.
class TermPaymentScreen extends StatefulWidget {
  final bool embedded;
  const TermPaymentScreen({super.key, this.embedded = false});

  @override
  State<TermPaymentScreen> createState() => _TermPaymentScreenState();
}

class _TermPaymentScreenState extends State<TermPaymentScreen> {
  late int _year;
  final Set<int> _months = <int>{};
  final Set<int> _payees = <int>{};
  List<_Payee> _people = const [];
  PrepayBill _bill = const PrepayBill([]);
  bool _loadingPeople = true;
  bool _gathering = false;
  bool _paying = false;
  int _gatherSeq = 0;

  static const _monthNames = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  @override
  void initState() {
    super.initState();
    _year = DateTime.now().year;
    _loadPeople();
  }

  /// Self (the logged-in account) plus siblings from /Listing/MySiblings.
  Future<void> _loadPeople() async {
    final session = UserSession.instance;
    final people = <_Payee>[];
    final selfId = session.currentStudentId;
    if (selfId != null) {
      people.add(_Payee(
          selfId, session.displayName.isEmpty ? 'Me' : session.displayName));
    }
    try {
      final resp = await Api.listingMySiblings();
      for (final r in findRecordList(resp).whereType<Map>()) {
        final id = (r['id'] is num) ? (r['id'] as num).toInt() : null;
        final name = pickField(r, ['text', 'name', 'studentName']);
        if (id != null && id != selfId && name.isNotEmpty) {
          people.add(_Payee(id, name));
        }
      }
    } catch (_) {/* siblings are optional */}
    if (!mounted) return;
    setState(() {
      _people = people;
      _payees
        ..clear()
        ..addAll(people.map((p) => p.id)); // default: pay for everyone
      _loadingPeople = false;
    });
  }

  Future<void> _gather() async {
    final seq = ++_gatherSeq;
    if (_months.isEmpty || _payees.isEmpty) {
      setState(() {
        _bill = const PrepayBill([]);
        _gathering = false;
      });
      return;
    }
    setState(() => _gathering = true);
    final bill = await PrepayService.gatherInvoices(
      studentIds: _payees.toList(),
      year: _year,
      months: _months.toList()..sort(),
    );
    if (!mounted || seq != _gatherSeq) return; // ignore stale result
    setState(() {
      _bill = bill;
      _gathering = false;
    });
  }

  Future<void> _pay() async {
    if (_months.isEmpty ||
        _bill.count == 0 ||
        _payees.isEmpty ||
        _paying ||
        _gathering ||
        _bill.failedRequests > 0) return;
    final session = UserSession.instance;
    if (session.paymentLocked) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'A payment is being processed. Check Payment History before trying again.')));
      return;
    }
    final ids = _payees.toList();
    final selectedMonths = _months.toList()..sort();
    final year = _year;
    // Confirm before charging.
    final c = context.appColors;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: const Text('Confirm payment'),
        content: Text(_bill.count == 0
            ? 'Continue to checkout for ${selectedMonths.length} month(s) and ${ids.length} student(s)? The gateway will show the final amount before payment.'
            : 'Estimated RM ${_bill.total.toStringAsFixed(2)}. The gateway confirms the final total for all selected months before payment.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Pay')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _paying = true);
    session.startPaymentLock();
    try {
      final start = await BoostPayment.start(PaymentIntent(
          term: TermPayment(
              studentIds: ids, year: year, months: selectedMonths)));
      if (!mounted) return;
      await BcpgWebViewScreen.open(context,
          paymentUrl: start.url, referenceId: start.referenceId ?? '');
      final result = await BoostPayment.confirm(referenceId: start.referenceId);
      if (result.outcome != PaymentOutcome.unknown) session.clearPaymentLock();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(result.message)));
      await UserSession.instance.refresh();
      await _gather();
    } catch (e) {
      session.clearPaymentLock();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Payment failed: ${friendlyError(e)}')),
      );
    } finally {
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final now = DateTime.now();
    final canPay = _bill.count > 0 &&
        _months.isNotEmpty &&
        _payees.isNotEmpty &&
        !_gathering &&
        !_paying &&
        _bill.failedRequests == 0;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (!widget.embedded)
            const AppHeader(title: 'Advance Payment', showBack: true),
          Expanded(
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                  Gaps.xl, Gaps.sm, Gaps.xl, widget.embedded ? 120 : 28),
              children: [
                _yearDropdown(c, now),
                const SizedBox(height: 16),
                _label(c, 'Select Month(s) to PAY'),
                const SizedBox(height: 8),
                _monthGrid(c, now),
                const SizedBox(height: 18),
                _label(c, 'Select Siblings to PAY'),
                const SizedBox(height: 8),
                if (_loadingPeople)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: LinearProgressIndicator(),
                  )
                else
                  _peopleList(c),
                const SizedBox(height: 18),
                _summaryAndPay(c, canPay),
                const SizedBox(height: 16),
                if (_gathering)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_bill.failedRequests > 0)
                  Column(children: [
                    const Text(
                        'Could not price every selected month. Please retry.'),
                    TextButton(onPressed: _gather, child: const Text('Retry')),
                  ])
                else if (_months.isNotEmpty && _bill.count == 0)
                  _emptyNote(c)
                else
                  for (final inv in _bill.invoices) _invoiceCard(c, inv),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _label(AppColors c, String t) => Text(t,
      style: TextStyle(
          color: c.textPrimary, fontWeight: FontWeight.w800, fontSize: 15));

  Widget _yearDropdown(AppColors c, DateTime now) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          isExpanded: true,
          value: _year,
          items: [
            for (final y in [now.year, now.year + 1, now.year + 2])
              DropdownMenuItem(value: y, child: Text('$y')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _year = v;
              _gatherSeq++;
              _gathering = false;
              _months.clear();
              _bill = const PrepayBill([]);
            });
          },
        ),
      ),
    );
  }

  Widget _monthGrid(AppColors c, DateTime now) {
    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.4,
      mainAxisSpacing: 4,
      children: [
        for (var m = 1; m <= 12; m++)
          _checkTile(
            c,
            _monthNames[m - 1],
            _months.contains(m),
            // Past months of the current year can't be prepaid.
            disabled: _year == now.year && m < now.month,
            onChanged: (sel) {
              setState(() {
                if (sel) {
                  _months.add(m);
                } else {
                  _months.remove(m);
                }
              });
              _gather();
            },
          ),
      ],
    );
  }

  Widget _peopleList(AppColors c) {
    if (_people.isEmpty) {
      return Text('No payable accounts found.',
          style: TextStyle(color: c.textSecondary));
    }
    return Column(
      children: [
        for (final p in _people)
          _checkTile(
            c,
            p.name,
            _payees.contains(p.id),
            onChanged: (sel) {
              setState(() {
                if (sel) {
                  _payees.add(p.id);
                } else {
                  _payees.remove(p.id);
                }
              });
              _gather();
            },
          ),
      ],
    );
  }

  Widget _checkTile(AppColors c, String label, bool value,
      {bool disabled = false, required ValueChanged<bool> onChanged}) {
    return InkWell(
      onTap: disabled ? null : () => onChanged(!value),
      borderRadius: BorderRadius.circular(Radii.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(children: [
          Icon(
            value ? AppIcons.check_circle : Icons.radio_button_unchecked,
            size: 20,
            color: disabled
                ? c.textMuted.withOpacity(0.4)
                : (value ? c.success : c.textMuted),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: disabled ? c.textMuted : c.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  Widget _summaryAndPay(AppColors c, bool canPay) {
    return Column(children: [
      Row(children: [
        Expanded(
          child: Text('Total Invoice(s) : ${_bill.count}',
              style:
                  TextStyle(color: c.textPrimary, fontWeight: FontWeight.w700)),
        ),
        Text(
            _bill.count == 0
                ? 'Total at checkout'
                : 'Estimate: RM ${_bill.total.toStringAsFixed(2)}',
            style:
                TextStyle(color: c.textPrimary, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: canPay ? _pay : null,
          style: FilledButton.styleFrom(
            backgroundColor: c.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          child: Text(
            _paying ? 'Opening checkout…' : 'Pay Now',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
          ),
        ),
      ),
    ]);
  }

  Widget _emptyNote(AppColors c) => Container(
        padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.border),
        ),
        child: Center(
          child: Text(
              'No fee quote is available for these selections. Choose another month or contact your club.',
              textAlign: TextAlign.center,
              style: TextStyle(color: c.textSecondary)),
        ),
      );

  Widget _invoiceCard(AppColors c, PrepayInvoice inv) {
    Widget kv(String k, String v, {bool strong = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(k, style: TextStyle(color: c.textMuted, fontSize: 11)),
            const SizedBox(height: 1),
            Text(v.isEmpty ? '-' : v,
                style: TextStyle(
                    color: strong ? c.primary : c.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ]),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: c.border),
        boxShadow: Shadows.card(c),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            kv('Inv No', inv.invoiceNo),
            kv('Period', inv.period),
            kv('Discount', inv.discount.toStringAsFixed(2)),
          ]),
        ),
        const SizedBox(width: 12),
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            kv('Inv Type', inv.invoiceType),
            kv('Name', inv.studentName),
            kv('Due Amt', inv.amount.toStringAsFixed(2), strong: true),
          ]),
        ),
      ]),
    );
  }
}
