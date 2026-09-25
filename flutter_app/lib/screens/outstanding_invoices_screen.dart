import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/boost_payment.dart';
import '../services/response_utils.dart';
import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/report_kit.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';
import 'payment/bcpg_webview_screen.dart';

int _intOf(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// Port of `frontend/app/pay-dues.tsx` (Expo v2.11.1) — "Pay Your Dues".
class OutstandingInvoicesScreen extends StatefulWidget {
  const OutstandingInvoicesScreen({super.key});
  @override
  State<OutstandingInvoicesScreen> createState() => _OutstandingInvoicesScreenState();
}

class _OutstandingInvoicesScreenState extends State<OutstandingInvoicesScreen>
    with UseApi<OutstandingInvoicesScreen> {
  String _type = '';
  // Opens showing every outstanding invoice, which is what the home dues card counts.
  bool _pendingOnly = false;
  final Set<int> _selected = {};
  bool _paying = false;

  late final _types = useApi(RnApi.invoiceTypes);
  late final _inv = useApi<List<Map<String, dynamic>>>(() async {
    final resp = await Api.outstandingFetch({
      'studentId': null,
      'studentName': null,
      'icNo': null,
      'startDate': null,
      'endDate': null,
      'eCenterId': null,
      'tCenterId': null,
      'sCenterId': null,
      'transactionType': _type.isEmpty ? null : _type,
    });
    final d = unwrapData(resp);
    return d is List ? d.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
  });

  @override
  void initState() {
    super.initState();
    _types;
    _inv;
  }

  Future<void> _payNow() async {
    if (_selected.isEmpty) {
      await notify(context, 'Select invoices', 'Choose at least one invoice to pay.');
      return;
    }
    final ids = _selected.toList();
    setState(() => _paying = true);
    UserSession.instance.startPaymentLock();
    try {
      final start = await BoostPayment.start(PaymentIntent(invoiceIds: ids));
      if (!mounted) return;
      await BcpgWebViewScreen.open(context,
          paymentUrl: start.url, referenceId: start.referenceId ?? '');
      // The browser never reports the result — verify by reference, then reconcile the list.
      final verdict = await BoostPayment.confirm(
        referenceId: start.referenceId,
        invoiceIds: ids,
        fetchOutstandingIds: (_) async => (await RnApi.outstanding()).map((r) => _intOf(r['invoiceId'])).toList(),
      );
      _inv.reload();
      if (!mounted) return;
      setState(() => _selected.clear());
      await notify(context, verdict.outcome == PaymentOutcome.paid ? 'Payment received' : 'Payment', verdict.message);
    } catch (e) {
      if (mounted) await notify(context, 'Payment failed', friendlyError(e));
    } finally {
      UserSession.instance.clearPaymentLock();
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final rows = _inv.data ?? const <Map<String, dynamic>>[];
    final filtered = _pendingOnly ? rows.where((r) => r['paymentStatus'] == 'Pending').toList() : rows;
    final dueTotal = filtered.fold<num>(0, (s, r) => s + RnApi.number(r['dueAmount']));
    final selectedDue = filtered
        .where((r) => _selected.contains(_intOf(r['invoiceId'])))
        .fold<num>(0, (s, r) => s + RnApi.number(r['dueAmount']));
    final typeOptions = <RkOption>[
      (id: '', text: 'All'),
      for (final t in _types.data ?? const <Map<String, dynamic>>[]) (id: '${t['id']}', text: '${t['text'] ?? ''}'),
    ];

    Widget centered(Widget child) => Center(child: Padding(padding: const EdgeInsets.all(40), child: child));
    Widget body;
    if (_inv.error != null) {
      body = centered(Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Ion.alertCircleOutline, size: 40, color: c.danger),
        const SizedBox(height: 10),
        Text(_inv.error!, textAlign: TextAlign.center, style: TextStyle(color: c.danger, fontSize: 14)),
      ]));
    } else if (_inv.loading) {
      body = Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: c.primary)));
    } else if (filtered.isEmpty) {
      body = centered(Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Ion.fileTrayOutline, size: 44, color: c.textMuted),
        const SizedBox(height: 10),
        Text('No outstanding invoices', style: TextStyle(color: c.textSecondary, fontSize: 14)),
      ]));
    } else {
      body = ListView.separated(
        padding: const EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 160),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, i) {
          final r = filtered[i];
          final id = _intOf(r['invoiceId']);
          // An invoice whose slip is already with the admin must not be paid twice.
          final locked = r['paymentStatus'] == 'Approval Pending';
          final on = !locked && _selected.contains(id);
          final desc = '${r['invoiceDescription'] ?? ''}';
          return Opacity(
            opacity: locked ? 0.72 : 1,
            child: Touchable(
              activeOpacity: locked ? 1 : 0.85,
              onPress: locked ? null : () => setState(() => on ? _selected.remove(id) : _selected.add(id)),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: rnCard(c),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(locked ? Ion.timeOutline : (on ? Ion.checkbox : Ion.squareOutline),
                        size: 22, color: locked ? c.textMuted : c.primary),
                  ),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${r['studentName'] ?? ''}'.isEmpty ? '—' : '${r['studentName']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.textPrimary)),
                      KV('Type', r['transactionType']),
                      KV('Period', r['period']),
                      KV('Due Amt', 'RM ${money2(RnApi.number(r['dueAmount']))}', strong: true),
                      KV('Status', r['paymentStatus']),
                      if (locked)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('Payment slip submitted — waiting for the club to approve it.',
                              style: TextStyle(
                                  fontSize: 11.5,
                                  color: c.textSecondary,
                                  fontWeight: FontWeight.w600,
                                  fontStyle: FontStyle.italic)),
                        ),
                      if (desc.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(desc,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: c.textSecondary)),
                        ),
                    ]),
                  ),
                ]),
              ),
            ),
          );
        },
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ScreenHeader(title: 'Pay Your Dues'),
        Container(
          margin: const EdgeInsets.fromLTRB(Gaps.xl, 4, Gaps.xl, 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.xl)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SelectField(
              label: 'Filter By Transaction Type',
              placeholder: 'All',
              value: _type,
              options: typeOptions,
              loading: _types.loading,
              onChange: (id, _) {
                setState(() {
                  _type = '$id';
                  _selected.clear();
                });
                _inv.reload();
              },
            ),
            const SizedBox(height: 10),
            Touchable(
              activeOpacity: 0.7,
              onPress: () => setState(() => _pendingOnly = !_pendingOnly),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Icon(_pendingOnly ? Ion.checkbox : Ion.checkboxOutline, size: 20, color: c.primary),
                  const SizedBox(width: 10),
                  Text('Show only Pending',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.textPrimary)),
                ]),
              ),
            ),
          ]),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, 6),
          padding: const EdgeInsets.all(14),
          decoration: rnCard(c),
          child: Column(children: [
            KV('Total Invoice(s)', '${filtered.length}'),
            KV('Due Amt', 'RM ${money2(dueTotal)}', strong: true),
          ]),
        ),
        Expanded(child: body),
        Container(
          padding: EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, bottom + 12 > 28 ? bottom + 12 : 28),
          decoration: BoxDecoration(color: c.background, border: Border(top: BorderSide(color: c.border))),
          child: Touchable(
            activeOpacity: 0.9,
            onPress: _paying ? null : _payNow,
            child: Container(
              constraints: const BoxConstraints(minHeight: 50),
              padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(999),
                boxShadow: Shadows.strong(c),
              ),
              child: _paying
                  ? const Center(
                      child: SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Ion.lockClosed, size: 14, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text('Pay Now (${_selected.length} selected) · RM ${money2(selectedDue)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      ),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }
}
