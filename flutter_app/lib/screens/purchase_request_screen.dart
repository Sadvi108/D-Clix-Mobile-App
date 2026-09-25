import 'package:flutter/material.dart';

import '../services/boost_payment.dart';
import '../services/purchase_service.dart';
import '../services/response_utils.dart';
import '../services/user_session.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/report_kit.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';
import 'payment/bcpg_webview_screen.dart';

/// Port of `frontend/app/purchase-request.tsx` (Expo v2.11.1).
///
/// A purchase is raised by paying for it: `/Bcpg/PayInvoices` carries the lines in
/// `purchaseItems`. There is no other create-purchase route in the mobile API.
class PurchaseRequestScreen extends StatefulWidget {
  const PurchaseRequestScreen({super.key});

  @override
  State<PurchaseRequestScreen> createState() => _PurchaseRequestScreenState();
}

class _PurchaseRequestScreenState extends State<PurchaseRequestScreen> with UseApi<PurchaseRequestScreen> {
  late final _products = useApi(PurchaseService.fetchProducts);

  /// productId -> quantity text.
  final Map<int, TextEditingController> _qty = {};
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _products;
  }

  @override
  void dispose() {
    for (final ctrl in _qty.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  TextEditingController _ctrl(int id) => _qty.putIfAbsent(id, () {
        final ctrl = TextEditingController();
        ctrl.addListener(() => setState(() {}));
        return ctrl;
      });

  int _n(int id) => int.tryParse(_qty[id]?.text ?? '') ?? 0;

  Future<void> _proceed() async {
    final rows = _products.data ?? const <PurchaseProduct>[];
    final selected = rows.where((p) => _n(p.productId) > 0).toList();
    if (selected.isEmpty) {
      await notify(context, 'Nothing selected', 'Enter a quantity for at least one item.');
      return;
    }
    final total = selected.fold<double>(0, (s, p) => s + _n(p.productId) * p.price);
    setState(() => _paying = true);
    final session = UserSession.instance;
    session.startPaymentLock();
    try {
      // Row count before paying, so the return leg can tell whether the request was raised.
      int? baseline;
      try {
        baseline = await PurchaseService.countRequests();
      } catch (_) {
        baseline = null;
      }
      final start = await BoostPayment.start(PaymentIntent(
        purchaseItems: [for (final p in selected) buildPurchaseLine(p, _n(p.productId))],
      ));
      if (!mounted) return;
      await BcpgWebViewScreen.open(context,
          paymentUrl: start.url, referenceId: start.referenceId ?? '');
      final verdict = await BoostPayment.confirm(
        referenceId: start.referenceId,
        purchaseBaseline: baseline,
        fetchPurchaseCount: PurchaseService.countRequests,
      );
      if (!mounted) return;
      final paid = verdict.outcome == PaymentOutcome.paid;
      await notify(
        context,
        paid ? 'Purchase confirmed' : 'Purchase',
        paid ? '${selected.length} item(s) · RM ${money2(total)}. Your academy will process the order.' : verdict.message,
      );
      if (paid) {
        for (final ctrl in _qty.values) {
          ctrl.clear();
        }
      }
    } catch (e) {
      if (mounted) await notify(context, 'Purchase failed', friendlyError(e));
    } finally {
      session.clearPaymentLock();
      if (mounted) setState(() => _paying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final rows = _products.data ?? const <PurchaseProduct>[];

    Widget centered(Widget child) => Center(child: Padding(padding: const EdgeInsets.all(40), child: child));

    Widget body;
    if (_products.loading) {
      body = Center(child: SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 3, color: c.primary)));
    } else if (_products.error != null) {
      body = centered(Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Ion.alertCircleOutline, size: 40, color: c.danger),
        const SizedBox(height: 10),
        Text(_products.error!, textAlign: TextAlign.center, style: TextStyle(color: c.danger, fontSize: 14)),
      ]));
    } else if (rows.isEmpty) {
      body = centered(Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Ion.cartOutline, size: 44, color: c.textMuted),
        const SizedBox(height: 10),
        Text('No products available.', style: TextStyle(color: c.textSecondary, fontSize: 14)),
      ]));
    } else {
      body = ListView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, 140 + bottom),
        children: [
          for (final p in rows)
            Builder(builder: (context) {
              final lineTotal = _n(p.productId) * p.price;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: rnCard(c),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          text: 'Type: ',
                          style: TextStyle(fontSize: 12, color: c.textSecondary, fontWeight: FontWeight.w600),
                          children: [
                            TextSpan(
                                text: p.category.isEmpty ? '—' : p.category,
                                style: TextStyle(color: c.textPrimary, fontWeight: FontWeight.w800)),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('Price: RM ${money2(p.price)}',
                        maxLines: 1, style: TextStyle(fontSize: 13, color: c.primary, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 8),
                  Text('Item: ${p.name.isEmpty ? '—' : p.name}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.textPrimary)),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    SizedBox(
                      width: 120,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const RkLabel('Qty'),
                        Container(
                          constraints: const BoxConstraints(minHeight: 46),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: c.surface,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: c.border),
                          ),
                          child: TextField(
                            controller: _ctrl(p.productId),
                            keyboardType: TextInputType.number,
                            cursorColor: c.primary,
                            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: c.textPrimary),
                            decoration: InputDecoration(
                              isDense: true,
                              filled: false,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                              hintText: '0',
                              hintStyle: TextStyle(color: c.textMuted),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const RkLabel('Total'),
                        Container(
                          constraints: const BoxConstraints(minHeight: 46),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                            color: c.surfaceAlt,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: c.border),
                          ),
                          child: Text('RM ${money2(lineTotal)}',
                              maxLines: 1,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: c.textPrimary)),
                        ),
                      ]),
                    ),
                  ]),
                ]),
              );
            }),
        ],
      );
    }

    return Scaffold(
      backgroundColor: c.background,
      body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const ScreenHeader(title: 'New Purchase Request'),
        Expanded(child: body),
        Container(
          padding: EdgeInsets.fromLTRB(Gaps.xl, 12, Gaps.xl, bottom + 12 > 28 ? bottom + 12 : 28),
          decoration: BoxDecoration(color: c.background, border: Border(top: BorderSide(color: c.border))),
          child: Touchable(
            activeOpacity: 0.9,
            onPress: _paying ? null : _proceed,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(vertical: 15),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: c.gradient),
                borderRadius: BorderRadius.circular(999),
                boxShadow: Shadows.strong(c),
              ),
              child: _paying
                  ? const Center(
                      child: SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)))
                  : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Ion.bagCheck, size: 20, color: Colors.white),
                      SizedBox(width: 8),
                      Text('Proceed to pay',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                    ]),
            ),
          ),
        ),
      ]),
    );
  }
}
