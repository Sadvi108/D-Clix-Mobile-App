import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../services/api.dart';
import '../services/response_utils.dart';
import '../services/rn_api.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/premium_kit.dart';
import '../widgets/report_kit.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';

/// Port of `frontend/app/(tabs)/collections.tsx` (Expo v2.11.1).
class InstructorCollectionsScreen extends StatefulWidget {
  const InstructorCollectionsScreen({super.key});
  @override
  State<InstructorCollectionsScreen> createState() => _InstructorCollectionsScreenState();
}

class _InstructorCollectionsScreenState extends State<InstructorCollectionsScreen>
    with UseApi<InstructorCollectionsScreen> {
  late final _counts = useApi(RnApi.collectionCount);
  bool _updating = false;

  @override
  void initState() {
    super.initState();
    _counts;
  }

  bool get _busy => _counts.loading || _updating;

  /// Open a type's live detail list (typeId 1=cash, 2=online/fpx, 3=bank-in slip).
  void _openList(int typeId, String label) =>
      context.push('/instructor/collections/$typeId?label=${Uri.encodeQueryComponent(label)}');

  /// Recalc all collection counts server-side, then refresh.
  Future<void> _update() async {
    if (_updating) return;
    setState(() => _updating = true);
    try {
      await Future.wait([1, 2, 3].map((t) async {
        final r = await Api.outstandingUpdateCollectionCount(t);
        final err = apiEnvelopeError(r);
        if (err != null) throw Exception(err);
      }));
      _counts.reload();
      if (mounted) await notify(context, 'Collections updated', 'Counts refreshed from the server.');
    } catch (e) {
      if (mounted) await notify(context, 'Update failed', friendlyError(e));
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final tabBarHeight = 62 + MediaQuery.paddingOf(context).bottom;
    final d = _counts.data ?? const <String, dynamic>{};
    int n(dynamic v) => RnApi.number(v).toInt();
    final types = [
      (
        typeId: 1,
        label: 'Cash Payments',
        hint: 'Collected at the centre',
        icon: Ion.cashOutline,
        tint: PremiumTint.green,
        count: n(d['cash'])
      ),
      (
        typeId: 2,
        label: 'Online Payments',
        hint: 'Card, FPX and e-wallet',
        icon: Ion.cardOutline,
        tint: PremiumTint.sky,
        count: n(d['fpx'])
      ),
      (
        typeId: 3,
        label: 'Payment Slips',
        hint: 'Bank-in slips to review',
        icon: Ion.documentAttachOutline,
        tint: PremiumTint.violet,
        count: n(d['dbt'])
      ),
    ];
    final total = types.fold<int>(0, (s, t) => s + t.count);
    final hasCounts = _counts.data != null;

    Widget countBadge(int value, Color tint) => Container(
          constraints: const BoxConstraints(minWidth: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: tint.hexA(c.isDark ? '2E' : '17'), borderRadius: BorderRadius.circular(999)),
          child: _busy && !hasCounts
              ? SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2, color: tint))
              : Text('$value', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: tint)),
        );

    return ColoredBox(
      color: c.background,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        PremiumHeader(
          title: 'Collections',
          subtitle: 'Payments received across your club',
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0x2EFFFFFF),
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: const Icon(Ion.wallet, size: 20, color: Colors.white),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            color: c.primary,
            onRefresh: _counts.reload,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.only(bottom: tabBarHeight + 24),
              children: [
                // Not pulled up under the header: the list viewport would clip it.
                Padding(
                  padding: const EdgeInsets.only(top: Gaps.lg),
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: Gaps.xl),
                    clipBehavior: Clip.antiAlias,
                    decoration: premiumSlate(c),
                    child: Stack(children: [
                      const SlateGlow(),
                      Padding(
                        padding: const EdgeInsets.all(18),
                        child: Row(children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              const Text('RECORDS TO REVIEW',
                                  style: TextStyle(
                                      color: Color(0xFFFDBA74),
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: 1.2)),
                              const SizedBox(height: 6),
                              Text(hasCounts ? '$total' : (_busy ? '…' : '—'),
                                  style:
                                      const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              Text(
                                  hasCounts
                                      ? '${types[0].count} cash · ${types[1].count} online · ${types[2].count} slips'
                                      : 'Counts load from the server',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 12.5)),
                            ]),
                          ),
                          const SizedBox(width: 12),
                          Semantics(
                            button: true,
                            label: 'Update Collection',
                            excludeSemantics: true,
                            child: Touchable(
                              onPress: _updating ? null : _update,
                              activeOpacity: 0.85,
                              child: Container(
                                constraints: const BoxConstraints(minHeight: 44),
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: c.primary,
                                  borderRadius: BorderRadius.circular(999),
                                  boxShadow: [
                                    BoxShadow(color: c.primary.hexA('66'), blurRadius: 14, offset: const Offset(0, 4))
                                  ],
                                ),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  if (_updating)
                                    const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  else
                                    const Icon(Ion.syncOutline, size: 15, color: Colors.white),
                                  const SizedBox(width: 6),
                                  Text(_updating ? 'Updating…' : 'Update Collection',
                                      style: const TextStyle(
                                          color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12.5)),
                                ]),
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ]),
                  ),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  if (_counts.error != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Gaps.xl, 16, Gaps.xl, 0),
                      child: ErrorState(message: _counts.error, onRetry: _counts.reload, compact: true),
                    ),
                  const SectionLabel('By payment type'),
                  GroupCard(children: [
                    for (final t in types)
                      PremiumRow(
                        icon: t.icon,
                        tint: t.tint,
                        title: t.label,
                        subtitle: t.hint,
                        trailing: countBadge(t.count, t.tint),
                        onTap: () => _openList(t.typeId, t.label),
                      ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Gaps.xl + 4, 14, Gaps.xl + 4, 0),
                    child: Text(
                        'Update Collection recalculates the counts on the server. Pull down to refresh what is shown.',
                        style: TextStyle(fontSize: 12, color: c.textMuted, height: 1.4)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

/// Port of `frontend/app/collection-list.tsx` — the live rows behind one collection type.
class CollectionListScreen extends StatefulWidget {
  final int typeId;
  final String label;
  const CollectionListScreen({super.key, required this.typeId, required this.label});
  @override
  State<CollectionListScreen> createState() => _CollectionListScreenState();
}

class _CollectionListScreenState extends State<CollectionListScreen> with UseApi<CollectionListScreen> {
  late final _list = useApi(() => RnApi.collectionCountList(widget.typeId));

  @override
  void initState() {
    super.initState();
    _list;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    dynamic first(Map r, List<String> keys) {
      for (final k in keys) {
        final v = r[k];
        if (v != null && '$v'.trim().isNotEmpty) return v;
      }
      return null;
    }

    return ReportScaffold<Map<String, dynamic>>(
      title: widget.label,
      subtitle: 'Live collection records',
      loading: _list.loading,
      error: _list.error,
      data: _list.data,
      emptyText: 'No collections recorded yet.',
      onRefresh: _list.reload,
      renderItem: (r, _) {
        final title = first(r, ['studentName', 'name', 'icNo', 'receiptNo']) ?? 'Collection';
        final amount = first(r, ['amount', 'receiptAmount', 'paidAmount']);
        final date = first(r, ['receiptDate', 'date', 'paymentDate']);
        return RkCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: c.primary, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: KV('', title, strong: true)),
            ]),
            if (r['icNo'] != null) KV('IC No', r['icNo']),
            if (first(r, ['transactionType', 'type']) != null) KV('Type', first(r, ['transactionType', 'type'])),
            if (r['period'] != null) KV('Period', r['period']),
            if (amount != null) KV('Amount', 'RM ${money2(RnApi.number(amount))}', strong: true),
            if (r['receiptNo'] != null) KV('Receipt No', r['receiptNo']),
            if (date != null) KV('Date', fmtDateGB(date)),
            if (r['status'] != null) KV('Status', r['status']),
            if (first(r, ['centerName', 'tcName']) != null) KV('Center', first(r, ['centerName', 'tcName'])),
          ]),
        );
      },
    );
  }
}
