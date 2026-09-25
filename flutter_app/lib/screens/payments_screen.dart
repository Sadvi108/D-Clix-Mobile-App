import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../services/api.dart';
import '../services/api_service.dart';
import '../services/boost_payment.dart';
import '../services/live_refresh.dart';
import '../services/receipt_pdf.dart';
import '../services/response_utils.dart';
import '../services/rn_api.dart';
import '../services/user_session.dart';
import '../services/web_download.dart';
import '../theme/app_theme.dart';
import '../theme/ion.dart';
import '../widgets/rn_kit.dart';
import '../widgets/use_api.dart';
import 'payment/bcpg_webview_screen.dart';

/// Advance-payment selection carried into the pay sheet (`TermPayContext` in payments.tsx).
class TermPayContext {
  /// Months that already have an invoice.
  final List<int> ids;
  final num total;
  final List<int> studentIds;
  final int year;
  final List<int> months;

  /// The selection includes months the academy hasn't invoiced yet.
  final bool estimated;
  const TermPayContext({
    required this.ids,
    required this.total,
    required this.studentIds,
    required this.year,
    required this.months,
    required this.estimated,
  });
}

/// A selected invoice plus the account it belongs to (`CartItem` in usePaymentCart.ts).
class _CartItem {
  final String key;
  final int studentId;
  final Map<String, dynamic> invoice;
  const _CartItem(this.key, this.studentId, this.invoice);
}

String _fmtDate(dynamic iso) {
  final s = '${iso ?? ''}';
  if (s.isEmpty) return '';
  final d = DateTime.tryParse(s);
  return d == null ? s : DateFormat('dd MMM yyyy').format(d);
}

int _intOf(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

/// Port of `frontend/app/(tabs)/payments.tsx` (Expo v2.11.1).
class PaymentsScreen extends StatefulWidget {
  final String initialTab;
  const PaymentsScreen({super.key, this.initialTab = 'pay'});
  @override
  State<PaymentsScreen> createState() => _PaymentsScreenState();
}

class _PaymentsScreenState extends State<PaymentsScreen>
    with UseApi<PaymentsScreen>, LiveRefreshMixin<PaymentsScreen> {
  late String _seg = const {'pay', 'prepay', 'history'}.contains(widget.initialTab) ? widget.initialTab : 'pay';
  final _range = RnApi.defaultRange();
  final Map<String, _CartItem> _cart = {};
  String? _busyPdf;
  ({int id, String name})? _activeAccount;
  int _prepayRefresh = 0;

  late final _siblings = useApi(RnApi.mySiblings);
  late final _dues = useApi(() => RnApi.outstanding(
      studentId: _accountId, startDate: _range.fromDate, endDate: _range.toDate));
  late final _history = useApi(() => RnApi.receipts({'fromDate': _range.fromDate, 'toDate': _range.toDate}));

  Map<String, dynamic> get _user => UserSession.instance.authData ?? const <String, dynamic>{};
  int? get _accountId => _activeAccount?.id ?? (_user['id'] == null ? null : _intOf(_user['id']));

  @override
  void initState() {
    super.initState();
    _siblings;
    _dues;
    _history;
  }

  @override
  void didUpdateWidget(covariant PaymentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) _seg = widget.initialTab;
  }

  // Never refetch the invoice list out from under a selection or an open prepay form.
  @override
  bool get canLiveRefresh => _cart.isEmpty && _seg != 'prepay' && !UserSession.instance.paymentLocked;

  @override
  Future<void> refreshLiveData() => Future.wait([_dues.reload(silent: true), _history.reload(silent: true)]);

  num get _cartTotal => _cart.values.fold<num>(0, (s, i) => s + RnApi.number(i.invoice['dueAmount']));

  void _setAccount(({int id, String name}) a) {
    setState(() => _activeAccount = a);
    _dues.reload();
  }

  Future<void> _openPdf(String key, Map<String, dynamic> receipt) async {
    setState(() => _busyPdf = key);
    final receiptNo = '${receipt['receiptNo'] ?? ''}';
    final fname = 'RECEIPT_${receiptNo.isEmpty ? 'receipt' : receiptNo}.pdf';
    try {
      // The id from Reports/Receipts is an invoiceId → ReceiptAsPDF's 3rd slot (paymentId 0).
      var bytes = await Api.utilitiesReceiptAsPdfBytes(
          clubId: _intOf(_user['clubId']), paymentId: 0, invoiceId: _intOf(receipt['id']));
      if (!_isPdf(bytes)) {
        // Server returned no document for this row — render it from the receipt rows instead.
        final pool = (_history.data ?? const []).cast<Map>();
        final group = ReceiptPdf.rowsForReceipt(receipt, pool);
        bytes = await ReceiptPdf.build(group.isEmpty ? [receipt] : group,
            clubName: UserSession.instance.clubDisplayName, logoUrl: UserSession.instance.clubPic);
      }
      if (!_isPdf(bytes)) throw Exception('Empty file received.');
      if (kIsWeb) {
        downloadBytesWeb(bytes, fname, 'application/pdf');
        return;
      }
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$fname');
      await file.writeAsBytes(bytes, flush: true);
      final res = await OpenFilex.open(file.path, type: 'application/pdf');
      if (res.type != ResultType.done) await Printing.sharePdf(bytes: bytes, filename: fname);
    } catch (e) {
      if (mounted) notify(context, 'Download failed', friendlyError(e));
    } finally {
      if (mounted) setState(() => _busyPdf = null);
    }
  }

  static bool _isPdf(List<int> b) => b.length > 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46;

  void _openSheet({TermPayContext? term}) {
    if (UserSession.instance.paymentLocked) {
      notify(context, 'Payment in progress',
          'A payment is still being confirmed. Check Payment History before paying again.');
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      barrierColor: context.appColors.overlay,
      builder: (_) => _PaySheet(
        term: term,
        invoiceIds: term?.ids ??
            _cart.values.map((i) => _intOf(i.invoice['invoiceId'])).where((id) => id > 0).toList(),
        total: term?.total ?? _cartTotal,
        onProceed: (method, slip) => _proceedToPay(term, method, slip),
      ),
    );
  }

  /// Returns true when the sheet should close.
  Future<bool> _proceedToPay(TermPayContext? term, String method, XFile? slip) async {
    final payingIds = term?.ids ?? _cart.values.map((i) => _intOf(i.invoice['invoiceId'])).where((id) => id > 0).toList();
    final hasTermSelection = term != null && term.months.isNotEmpty;
    if (payingIds.isEmpty && !hasTermSelection) {
      await notify(context, 'Select invoices', 'Choose at least one invoice to pay.');
      return false;
    }
    try {
      if (method != 'bankin') {
        // One gateway session for everything selected; /Bcpg bills un-invoiced advance months too.
        final start = await _startPayment(payingIds, term);
        if (!mounted) return true;
        Navigator.of(context).pop(); // close the sheet before the gateway opens
        await BcpgWebViewScreen.open(context,
            paymentUrl: start.url, referenceId: start.referenceId ?? '');
        if (!mounted) return false;
        // The browser never says whether the payment went through: verify, then reconcile
        // against every account in this payment, not just the active chip.
        final accounts = term?.studentIds ??
            _cart.values.map((i) => i.studentId).where((id) => id > 0).toSet().toList();
        final verdict = await BoostPayment.confirm(
          referenceId: start.referenceId,
          invoiceIds: payingIds,
          studentIds: accounts.isEmpty ? [_accountId] : accounts,
          fetchOutstandingIds: (sid) async => (await RnApi.outstanding(
                  studentId: sid, startDate: _range.fromDate, endDate: _range.toDate))
              .map((r) => _intOf(r['invoiceId']))
              .toList(),
        );
        if (verdict.outcome == PaymentOutcome.unknown) {
          UserSession.instance.startPaymentLock();
        } else {
          UserSession.instance.clearPaymentLock();
        }
        _afterPaid(term);
        if (mounted) {
          await notify(context, verdict.outcome == PaymentOutcome.paid ? 'Payment received' : 'Payment', verdict.message);
        }
        return false;
      }
      if (slip == null) {
        await notify(context, 'Payment slip required', 'Attach your bank-in slip first.');
        return false;
      }
      // Bank-in goes through the legacy multipart route, which bills invoice ids only.
      if (payingIds.isEmpty) {
        await notify(context, 'Not available for these months',
            "A bank-in slip can only be submitted against issued invoices. Pay online to settle months your academy hasn't invoiced yet.");
        return false;
      }
      final result = await ApiService.postMultipart(
        '/Outstanding/PayInvoices?PayTermPayments=${term != null}&PurchaseItems=false',
        {'PaymentMethod': '1'},
        repeatedFields: {'InvoiceIds': payingIds.map((id) => '$id').toList()},
        uploads: [(name: slip.name, bytes: await slip.readAsBytes())],
      );
      final error = apiEnvelopeError(result);
      if (error != null) throw Exception(error);
      if (!mounted) return true;
      Navigator.of(context).pop();
      _afterPaid(term);
      await notify(context, 'Submitted', 'Your payment slip has been submitted for verification.');
      return false;
    } catch (e) {
      if (mounted) await notify(context, 'Payment failed', friendlyError(e));
      return false;
    }
  }

  /// `api.startPayment`: prefer /Bcpg, fall back to the legacy online route when the Boost
  /// routes are missing (404/405). A term selection has no legacy equivalent.
  Future<PaymentStart> _startPayment(List<int> invoiceIds, TermPayContext? term) async {
    try {
      return await BoostPayment.start(PaymentIntent(
        invoiceIds: invoiceIds,
        term: term == null
            ? null
            : TermPayment(studentIds: term.studentIds, year: term.year, months: term.months),
      ));
    } on ApiException catch (e) {
      if (e.statusCode != 404 && e.statusCode != 405) rethrow;
      if (term != null) {
        throw const BoostPaymentException(
            'This server does not support the Boost gateway, which is what handles advance months and purchases. Pay issued invoices instead.');
      }
      final res = await ApiService.postMultipart(
        '/Outstanding/PayInvoices?PayTermPayments=false&PurchaseItems=false',
        {'PaymentMethod': '2'},
        repeatedFields: {'InvoiceIds': invoiceIds.map((id) => '$id').toList()},
      );
      final url = unwrapData(res);
      if (url is! String || url.isEmpty) throw const BoostPaymentException('No payment link was returned.');
      return PaymentStart(url: url, referenceId: BoostPayment.extractReferenceId(url));
    }
  }

  void _afterPaid(TermPayContext? term) {
    setState(() {
      if (term != null) {
        _prepayRefresh++;
      } else {
        _cart.clear();
      }
    });
    _dues.reload();
    _history.reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final session = context.watch<UserSession>();
    final user = session.authData ?? const <String, dynamic>{};
    final top = MediaQuery.paddingOf(context).top;
    final tabBarHeight = 62 + MediaQuery.paddingOf(context).bottom;
    final isActive = '${user['status'] ?? ''}'.trim().toLowerCase() != 'inactive';
    final invoices = _dues.data ?? const <Map<String, dynamic>>[];
    final accountId = _accountId;

    final accounts = <({int id, String name})>[
      (id: _intOf(user['id']), name: '${user['name'] ?? ''}'),
      for (final s in _siblings.data ?? const <Map<String, dynamic>>[]) (id: _intOf(s['id']), name: '${s['text'] ?? ''}'),
    ];
    final seen = <int>{};
    accounts.retainWhere((a) => seen.add(a.id));

    BoxDecoration cardDeco({bool selected = false}) => BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.lg),
          boxShadow: Shadows.soft(c),
          border: selected
              ? Border.all(color: c.primary, width: 1.5)
              : (c.isDark ? Border.all(color: c.border) : null),
        );

    Widget emptyTxt(String t) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 30),
          child: Text(t, textAlign: TextAlign.center, style: TextStyle(color: c.textSecondary, fontSize: 13)),
        );

    final body = <Widget>[];
    if (_seg == 'pay') {
      body.add(SizedBox(
        height: 46,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.only(bottom: 12),
          itemCount: accounts.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, i) {
            final a = accounts[i];
            final on = accountId == a.id;
            return Touchable(
              onPress: () => _setAccount(a),
              child: Container(
                constraints: const BoxConstraints(maxWidth: 160),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: on ? c.primary : c.surfaceAlt,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: on ? c.primary : c.border),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Ion.personCircleOutline, size: 16, color: on ? Colors.white : c.primary),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(a.name.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: on ? Colors.white : c.textPrimary)),
                  ),
                ]),
              ),
            );
          },
        ),
      ));
      body.add(Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Touchable(
          onPress: () => context.push('/autopay'),
          child: Container(
            padding: const EdgeInsets.all(13),
            decoration: cardDeco().copyWith(borderRadius: BorderRadius.circular(Radii.md)),
            child: Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                child: Icon(Ion.syncCircleOutline, size: 20, color: c.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Auto Pay',
                      maxLines: 1, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: c.textPrimary)),
                  const SizedBox(height: 2),
                  Text('Settle your fees automatically each month',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 11, color: c.textSecondary)),
                ]),
              ),
              const SizedBox(width: 12),
              Icon(Ion.chevronForward, size: 18, color: c.textMuted),
            ]),
          ),
        ),
      ));
      if (_dues.loading) body.add(const SkeletonList(rows: 4, lines: 2, padding: EdgeInsets.only(top: 4)));
      if (!_dues.loading && _dues.error != null && invoices.isEmpty) {
        body.add(ErrorState(message: _dues.error, onRetry: _dues.reload));
      } else if (!_dues.loading && invoices.isEmpty) {
        body.add(emptyTxt('No outstanding invoices.'));
      }
      if (!_dues.loading) {
        for (final inv in invoices) {
          final key = '$accountId:${inv['invoiceId']}';
          final selected = _cart.containsKey(key);
          body.add(Container(
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            decoration: cardDeco(selected: selected),
            child: Touchable(
              activeOpacity: 0.8,
              onPress: () => setState(() {
                if (selected) {
                  _cart.remove(key);
                } else {
                  _cart[key] = _CartItem(key, accountId ?? 0, inv);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Icon(selected ? Ion.checkbox : Ion.squareOutline, size: 22, color: selected ? c.primary : c.textMuted),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text('#${inv['invoiceId'] ?? ''}',
                            style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('${inv['transactionType'] ?? ''}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 11, color: c.primary, fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Text(
                          '${inv['invoiceDescription'] ?? ''}'.isNotEmpty
                              ? '${inv['invoiceDescription']}'
                              : '${inv['period'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: c.textPrimary, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${inv['period'] ?? ''} · ${_fmtDate(inv['invoiceDate'])} · ${inv['paymentStatus'] ?? ''}',
                          style: TextStyle(fontSize: 11, color: c.textSecondary)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text('RM ${localeNum(RnApi.number(inv['dueAmount']))}',
                      maxLines: 1,
                      style: TextStyle(fontSize: 15, color: c.textPrimary, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ));
        }
      }
    }

    if (_seg == 'prepay') {
      body.add(_PrepaySegment(
        key: ValueKey('prepay-$_prepayRefresh'),
        user: user,
        siblings: _siblings.data ?? const [],
        onPay: (term) => _openSheet(term: term),
      ));
    }

    if (_seg == 'history') {
      final rows = session.scopedRows(_history.data).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();
      if (_history.loading) body.add(const SkeletonList(rows: 4, lines: 2, padding: EdgeInsets.only(top: 4)));
      if (!_history.loading && _history.error != null && rows.isEmpty) {
        body.add(ErrorState(message: _history.error, onRetry: _history.reload));
      } else if (!_history.loading && rows.isEmpty) {
        body.add(emptyTxt('No receipts found.'));
      }
      if (!_history.loading) {
        for (var i = 0; i < rows.length; i++) {
          final p = rows[i];
          final k = 'rec-${p['id']}-$i';
          body.add(Container(
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            decoration: cardDeco(),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.all(14),
                child: Row(children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: c.isDark ? const Color(0xFF064E3B) : const Color(0xFFD1FAE5),
                    ),
                    child: Icon(Ion.checkmark, size: 16, color: c.success),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${p['paymentMethod'] ?? ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: c.textPrimary, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('${_fmtDate(p['receiptDate'])} · ${p['tcName'] ?? ''} · #${p['receiptNo'] ?? ''}',
                          style: TextStyle(fontSize: 11, color: c.textSecondary)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  Text('RM ${localeNum(RnApi.number(p['receiptAmount']))}',
                      maxLines: 1,
                      style: TextStyle(fontSize: 15, color: c.textPrimary, fontWeight: FontWeight.w800)),
                ]),
              ),
              if (isActive)
                Touchable(
                  onPress: _busyPdf == k ? null : () => _openPdf(k, p),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(border: Border(top: BorderSide(color: c.border))),
                    child: _busyPdf == k
                        ? Center(
                            child: SizedBox(
                                width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: c.primary)))
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Ion.downloadOutline, size: 14, color: c.primary),
                            const SizedBox(width: 5),
                            Text('Receipt PDF',
                                style: TextStyle(color: c.primary, fontSize: 12, fontWeight: FontWeight.w700)),
                          ]),
                  ),
                ),
            ]),
          ));
        }
      }
    }

    return ColoredBox(
      color: c.background,
      child: Stack(children: [
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: EdgeInsets.fromLTRB(Gaps.xl, top + 14, Gaps.xl, 14),
            child: Row(children: [
              const TabRootBackButton(),
              Expanded(
                child: Text('Fees & Payments',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.5, color: c.textPrimary)),
              ),
              Touchable(
                onPress: () {
                  _dues.reload();
                  _history.reload();
                },
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                  child: Icon(Ion.refreshOutline, size: 20, color: c.primary),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.xl, 0, Gaps.xl, 12),
            child: Row(children: [
              for (final s in const [('pay', 'Pay'), ('prepay', 'Advance Payment'), ('history', 'History')]) ...[
                if (s.$1 != 'pay') const SizedBox(width: 8),
                Expanded(
                  child: Touchable(
                    onPress: () => setState(() => _seg = s.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                      decoration: BoxDecoration(
                        color: _seg == s.$1 ? c.primary : c.surfaceAlt,
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                      child: Text(s.$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: _seg == s.$1 ? Colors.white : c.textSecondary)),
                    ),
                  ),
                ),
              ],
            ]),
          ),
          Expanded(
            child: RefreshIndicator(
              color: c.primary,
              onRefresh: () => Future.wait([_dues.reload(), _history.reload()]),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(Gaps.xl, Gaps.xl, Gaps.xl, tabBarHeight + 140),
                children: body,
              ),
            ),
          ),
        ]),

        // Bottom Pay bar — shown when the cart has items
        if (_seg == 'pay' && _cart.isNotEmpty)
          Positioned(
            left: 0,
            right: 0,
            bottom: tabBarHeight,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.xl, vertical: 14),
              decoration: BoxDecoration(
                color: c.surface,
                border: Border(top: BorderSide(color: c.border)),
                boxShadow: Shadows.card(c),
              ),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${_cart.length} selected',
                        style: TextStyle(fontSize: 11, color: c.textSecondary, fontWeight: FontWeight.w600)),
                    Text('RM ${localeNum(_cartTotal)}',
                        style: TextStyle(fontSize: 20, color: c.textPrimary, fontWeight: FontWeight.w800)),
                  ]),
                ),
                const SizedBox(width: 12),
                Touchable(
                  onPress: () => _openSheet(),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: c.gradient),
                      borderRadius: BorderRadius.circular(Radii.md),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Pay', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                      SizedBox(width: 8),
                      Icon(Ion.arrowForward, size: 16, color: Colors.white),
                    ]),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// "Make Payment" sheet — Boost online, or Direct Bank-In with a slip.
class _PaySheet extends StatefulWidget {
  final TermPayContext? term;
  final List<int> invoiceIds;
  final num total;
  final Future<bool> Function(String method, XFile? slip) onProceed;
  const _PaySheet({required this.term, required this.invoiceIds, required this.total, required this.onProceed});

  @override
  State<_PaySheet> createState() => _PaySheetState();
}

class _PaySheetState extends State<_PaySheet> {
  String _method = 'online';
  XFile? _slip;
  bool _paying = false;

  Future<void> _pick(ImageSource source) async {
    try {
      final img = await ImagePicker().pickImage(source: source, imageQuality: 60);
      if (img != null && mounted) setState(() => _slip = img);
    } catch (e) {
      if (mounted) notify(context, 'Could not pick image', friendlyError(e));
    }
  }

  Future<void> _proceed() async {
    setState(() => _paying = true);
    final close = await widget.onProceed(_method, _slip);
    if (!mounted) return;
    setState(() => _paying = false);
    if (close) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final term = widget.term;
    final bottom = MediaQuery.paddingOf(context).bottom;

    Widget hint(IconData icon, String text, {double iconSize = 18, Color? iconColor}) => Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
          child: Row(children: [
            Icon(icon, size: iconSize, color: iconColor ?? c.textSecondary),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: c.textSecondary, height: 18 / 13))),
          ]),
        );

    TextSpan strong(String t) => TextSpan(text: t, style: TextStyle(color: c.primary, fontWeight: FontWeight.w800));

    return PopScope(
      canPop: !_paying,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .92),
        padding: EdgeInsets.fromLTRB(22, 22, 22, 24 + bottom + MediaQuery.viewInsetsOf(context).bottom),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(color: c.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(children: [
              Expanded(
                child: Text('Make Payment',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: c.textPrimary)),
              ),
              Touchable(
                onPress: _paying ? null : () => Navigator.of(context).pop(),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
                  child: Icon(Ion.close, size: 20, color: c.textPrimary),
                ),
              ),
            ]),
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 18),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text.rich(TextSpan(
                  text: term != null ? 'Paying Month(s) : ' : 'Paying Invoice(s) : ',
                  style: TextStyle(fontSize: 14, color: c.textSecondary, fontWeight: FontWeight.w600),
                  children: [strong('${term != null ? term.months.length : widget.invoiceIds.length}')],
                )),
                Text.rich(TextSpan(
                  text: (term?.estimated ?? false) ? 'Est. Amt : ' : 'Paying Amt : ',
                  style: TextStyle(fontSize: 14, color: c.textSecondary, fontWeight: FontWeight.w600),
                  children: [strong(widget.total.toStringAsFixed(2))],
                )),
              ]),
            ),
            if (term != null)
              hint(
                Ion.calendarOutline,
                term.estimated
                    ? "Advance payment — some of these months aren't invoiced yet, so the payment page confirms the final amount."
                    : 'Advance payment — settling upcoming months ahead of time.',
                iconSize: 16,
                iconColor: c.primary,
              ),

            // Method toggles. The online method is the Boost gateway.
            for (final m in const [
              (id: 'online', label: 'Boost (online payment)', icon: Ion.walletOutline),
              (id: 'bankin', label: 'Direct Bank-In', icon: Ion.receiptOutline),
            ])
              Padding(
                padding: EdgeInsets.only(bottom: m.id == 'bankin' ? 18 : 10),
                child: Touchable(
                  activeOpacity: 0.7,
                  onPress: _paying ? null : () => setState(() => _method = m.id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                    decoration: BoxDecoration(
                      color: _method == m.id ? c.primary.hexA(c.isDark ? '26' : '12') : c.surfaceAlt,
                      borderRadius: BorderRadius.circular(Radii.md),
                      border: Border.all(color: _method == m.id ? c.primary : Colors.transparent, width: 1.5),
                    ),
                    child: Row(children: [
                      Icon(m.icon, size: 18, color: _method == m.id ? c.primary : c.textMuted),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(m.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: c.textPrimary)),
                      ),
                      const SizedBox(width: 10),
                      Icon(_method == m.id ? Ion.checkmarkCircle : Ion.ellipseOutline,
                          size: 22, color: _method == m.id ? c.success : c.textMuted),
                    ]),
                  ),
                ),
              ),

            if (_method != 'bankin')
              hint(Ion.walletOutline, "You'll be taken to the secure Boost payment gateway to complete this payment.")
            else ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text('Select Paymentslip',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.textPrimary)),
              ),
              if (_slip != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(Radii.lg)),
                  child: Stack(children: [
                    FutureBuilder(
                      future: _slip!.readAsBytes(),
                      builder: (_, snap) => SizedBox(
                        height: 180,
                        width: double.infinity,
                        child: snap.hasData ? Image.memory(snap.data!, fit: BoxFit.cover) : ColoredBox(color: c.surfaceAlt),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Touchable(
                        onPress: () => setState(() => _slip = null),
                        child: Container(
                          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                          child: Icon(Ion.closeCircle, size: 24, color: c.danger),
                        ),
                      ),
                    ),
                  ]),
                )
              else
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(Radii.lg),
                    border: Border.all(color: c.border, width: 1.5),
                  ),
                  child: Column(children: [
                    Icon(Ion.camera, size: 36, color: c.textMuted),
                    const SizedBox(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      for (final b in [
                        (label: 'Gallery', icon: Ion.images, source: ImageSource.gallery),
                        (label: 'Camera', icon: Ion.camera, source: ImageSource.camera),
                      ]) ...[
                        if (b.label == 'Camera') const SizedBox(width: 12),
                        Touchable(
                          onPress: () => _pick(b.source),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: c.surfaceAlt,
                              borderRadius: BorderRadius.circular(Radii.md),
                              border: Border.all(color: c.border),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(b.icon, size: 18, color: c.primary),
                              const SizedBox(width: 6),
                              Text(b.label, style: TextStyle(color: c.primary, fontWeight: FontWeight.w700, fontSize: 14)),
                            ]),
                          ),
                        ),
                      ],
                    ]),
                  ]),
                ),
            ],

            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Touchable(
                onPress: _paying ? null : _proceed,
                activeOpacity: 0.9,
                child: Container(
                  constraints: const BoxConstraints(minHeight: 52),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: c.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(Radii.md),
                    boxShadow: Shadows.strong(c),
                  ),
                  child: _paying
                      ? const Center(
                          child: SizedBox(
                              width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white)))
                      : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          const Icon(Ion.lockClosed, size: 14, color: Colors.white),
                          const SizedBox(width: 8),
                          Text(_method != 'bankin' ? 'Proceed to pay' : 'Submit Slip',
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
                        ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_method == 'bankin' ? 'VERIFIED BY YOUR ACADEMY' : 'SECURED BY BOOST',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: c.textMuted, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1)),
            ),
          ]),
        ),
      ),
    );
  }
}

const _monthAbbr = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

int _termMonth(Map t) {
  final d = DateTime.tryParse('${t['invoiceDate'] ?? ''}');
  if (d != null) return d.month;
  final period = '${t['period'] ?? ''}'.toLowerCase();
  final idx = _monthAbbr.indexWhere((m) => period.startsWith(m.toLowerCase()));
  return idx >= 0 ? idx + 1 : 0;
}

/// Advance Payment: a yearly month grid. On the Boost gateway every quoted month is payable,
/// including months the academy hasn't invoiced yet (the term model bills them).
class _PrepaySegment extends StatefulWidget {
  final Map<String, dynamic> user;
  final List<Map<String, dynamic>> siblings;
  final ValueChanged<TermPayContext> onPay;
  const _PrepaySegment({super.key, required this.user, required this.siblings, required this.onPay});

  @override
  State<_PrepaySegment> createState() => _PrepaySegmentState();
}

class _PrepaySegmentState extends State<_PrepaySegment> with UseApi<_PrepaySegment> {
  final _thisYear = DateTime.now().year;
  late int _year = _thisYear;
  late final Set<int> _selAccts = {_intOf(widget.user['id'])};
  final Set<int> _selMonths = {};

  late final _terms = useApi<List<Map<String, dynamic>>>(_fetch);

  Future<List<Map<String, dynamic>>> _fetch() async {
    if (_selAccts.isEmpty) return const [];
    final resp = await Api.outstandingFetchTermPayments({
      'studentIds': _selAccts.toList(),
      'year': _year,
      'months': List.generate(12, (i) => i + 1),
    });
    final data = unwrapData(resp);
    return data is List ? data.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList() : const [];
  }

  @override
  void initState() {
    super.initState();
    _terms;
  }

  // Month numbers mean different invoices in a different year, and different amounts for a
  // different set of siblings — drop the selection on either change.
  void _changed(VoidCallback fn) {
    setState(() {
      fn();
      _selMonths.clear();
    });
    _terms.reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.appColors;
    final accounts = <({int id, String name})>[
      (id: _intOf(widget.user['id']), name: '${widget.user['name'] ?? ''}'),
      for (final s in widget.siblings) (id: _intOf(s['id']), name: '${s['text'] ?? ''}'),
    ];
    final seen = <int>{};
    accounts.retainWhere((a) => seen.add(a.id));

    final rows = _terms.data ?? const <Map<String, dynamic>>[];
    final uninvoicedMonths = rows.where((r) => _intOf(r['invoiceId']) <= 0).map(_termMonth).toSet();
    final availMonths = rows.map(_termMonth).toSet();
    final chosen = rows.where((r) => _selMonths.contains(_termMonth(r))).toList();
    final totalInvoices = chosen.length;
    final dueAmount = chosen.fold<num>(0, (s, r) => s + RnApi.number(r['dueAmount']));
    final estimated = chosen.any((r) => _intOf(r['invoiceId']) <= 0);

    Widget label(String t, {double top = 0}) => Padding(
          padding: EdgeInsets.only(top: top, bottom: 12),
          child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.textPrimary)),
        );

    Widget navBtn(IconData icon, bool enabled, VoidCallback onTap) => Touchable(
          onPress: enabled ? onTap : null,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: c.surfaceAlt, shape: BoxShape.circle),
            child: Icon(icon, size: 18, color: enabled ? c.primary : c.textMuted),
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 14),
        child: Text('Advance Payment', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: c.textPrimary)),
      ),
      Container(
        margin: const EdgeInsets.only(bottom: 18),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(Radii.md),
          border: Border.all(color: c.border),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          navBtn(Ion.chevronBack, _year > _thisYear, () => _changed(() => _year--)),
          Text('$_year', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: c.textPrimary)),
          navBtn(Ion.chevronForward, true, () => _changed(() => _year++)),
        ]),
      ),
      label('Select Month(s) to PAY'),
      if (_terms.loading)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 20),
          child: Center(
              child: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: c.primary))),
        )
      else ...[
        if (_terms.error != null) ErrorState(message: _terms.error, onRetry: _terms.reload, compact: true),
        LayoutBuilder(builder: (context, box) {
          return Wrap(children: [
            for (var i = 0; i < 12; i++)
              Builder(builder: (context) {
                final m = i + 1;
                final available = availMonths.contains(m);
                final selected = available && _selMonths.contains(m);
                final projected = available && uninvoicedMonths.contains(m);
                return SizedBox(
                  width: box.maxWidth / 4,
                  child: Touchable(
                    activeOpacity: 0.7,
                    onPress: available
                        ? () => setState(() => selected ? _selMonths.remove(m) : _selMonths.add(m))
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Row(children: [
                        Icon(selected ? Ion.radioButtonOn : Ion.radioButtonOff,
                            size: 20, color: !available ? c.border : (selected ? c.primary : c.textMuted)),
                        const SizedBox(width: 6),
                        Text('${_monthAbbr[i]}${projected ? '*' : ''}',
                            style: TextStyle(
                                fontSize: 14,
                                color: available ? c.textPrimary : c.textMuted,
                                fontWeight: available ? FontWeight.w700 : FontWeight.w500)),
                      ]),
                    ),
                  ),
                );
              }),
          ]);
        }),
        if (uninvoicedMonths.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
            child: Row(children: [
              Icon(Ion.informationCircleOutline, size: 15, color: c.textSecondary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                    "Months marked * haven't been invoiced yet. You can still pay them in advance — the amount shown is your academy's standard fee, and the payment page confirms the final amount before you pay.",
                    style: TextStyle(fontSize: 13, color: c.textSecondary, height: 18 / 13)),
              ),
            ]),
          ),
      ],
      label('Select Siblings to PAY', top: 20),
      for (final a in accounts)
        Touchable(
          activeOpacity: 0.7,
          onPress: () => _changed(() => _selAccts.contains(a.id) ? _selAccts.remove(a.id) : _selAccts.add(a.id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(children: [
              Icon(_selAccts.contains(a.id) ? Ion.checkmarkCircle : Ion.ellipseOutline,
                  size: 24, color: _selAccts.contains(a.id) ? c.success : c.textMuted),
              const SizedBox(width: 12),
              Expanded(
                child: Text(a.name.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.textPrimary)),
              ),
            ]),
          ),
        ),
      Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 16),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text('Total Month(s) : $totalInvoices',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.textPrimary)),
          Text('${estimated ? 'Est. Amt : ' : 'Due Amt : '}${dueAmount.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: c.textPrimary)),
        ]),
      ),
      if (totalInvoices > 0)
        Touchable(
          activeOpacity: 0.9,
          onPress: () => widget.onPay(TermPayContext(
            // Only real invoice ids go in `ids`; every selected month rides the term model.
            ids: chosen.map((r) => _intOf(r['invoiceId'])).where((id) => id > 0).toList(),
            total: dueAmount,
            studentIds: _selAccts.toList(),
            year: _year,
            months: chosen.map(_termMonth).where((m) => m > 0).toSet().toList(),
            estimated: estimated,
          )),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: c.gradient),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Ion.lockClosed, size: 14, color: Colors.white),
              const SizedBox(width: 8),
              Text('Pay Now · ${estimated ? '~' : ''}RM ${dueAmount.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white)),
            ]),
          ),
        )
      else
        Opacity(
          opacity: 0.7,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(color: c.surfaceAlt, borderRadius: BorderRadius.circular(Radii.md)),
            child: Text('Select month(s) to pay',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: c.textMuted)),
          ),
        ),
    ]);
  }
}
