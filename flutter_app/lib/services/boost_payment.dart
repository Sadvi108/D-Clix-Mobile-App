import 'dart:async';

import 'api_service.dart';
import 'response_utils.dart';

/// Boost payment gateway, through the BACKEND's `/Bcpg/*` routes.
///
/// This replaces the previous direct mobile→Boost client, which signed each request with an
/// HMAC over a **merchant secret compiled into the app**. That secret shipped inside the
/// APK: anyone who decompiled it could extract the credential and forge requests against
/// the merchant account. The server holds the secret now and the app only ever asks the
/// backend for a checkout URL.
///
/// Contract (probed live — see docs/ARCHITECTURE.md):
///   POST /Bcpg/PayInvoices   JSON {invoiceIds, payTermPayments, purchaseItems} -> URL in `data`
///   GET  /Bcpg/VerifyPayment/{ref}                                   -> bare { status }
/// `/Bcpg` is not deployed to production, so those calls go to the UAT host, which is the
/// same database — see [ApiService.boostBaseUrl].

/// Advance ("term") months: real invoices may not exist for these yet.
class TermPayment {
  final List<int> studentIds;
  final int year;
  final List<int> months;
  const TermPayment(
      {required this.studentIds, required this.year, required this.months});

  bool get isEmpty => studentIds.isEmpty || months.isEmpty;
  Map<String, dynamic> toJson() =>
      {'studentIds': studentIds, 'year': year, 'months': months};
}

/// One line of a purchase request — the API's `PurchaseRequestLineViewModel`.
///
/// Field names are the server's, verified against the UAT Swagger: `qty` and `price`,
/// not `quantity`/`amount`. Getting these wrong would have the gateway bill a line the
/// server read as zero.
class PurchaseItem {
  final int id;
  final int purchaseRequestId;
  final int productId;
  final int qty;
  final double price;
  final double? unitTax;
  final double? totalTax;
  final double totalAmount;

  const PurchaseItem({
    this.id = 0,
    this.purchaseRequestId = 0,
    required this.productId,
    this.qty = 1,
    required this.price,
    this.unitTax,
    this.totalTax,
    required this.totalAmount,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'purchaseRequestId': purchaseRequestId,
        'productId': productId,
        'qty': qty,
        'price': price,
        'unitTax': unitTax,
        'totalTax': totalTax,
        'totalAmount': totalAmount,
      };
}

/// Everything one gateway session may bill.
class PaymentIntent {
  final List<int> invoiceIds;
  final TermPayment? term;
  final List<PurchaseItem> purchaseItems;

  const PaymentIntent({
    this.invoiceIds = const [],
    this.term,
    this.purchaseItems = const [],
  });

  bool get isEmpty =>
      invoiceIds.where((i) => i > 0).isEmpty &&
      (term == null || term!.isEmpty) &&
      purchaseItems.isEmpty;
}

class PaymentStart {
  final String url;
  final String? referenceId;
  const PaymentStart({required this.url, this.referenceId});
}

enum PaymentOutcome { paid, unpaid, unknown }

class PaymentResult {
  final PaymentOutcome outcome;
  final String? gatewayStatus;
  final String message;
  const PaymentResult(this.outcome, this.message, {this.gatewayStatus});
}

class BoostPaymentException implements Exception {
  final String message;
  const BoostPaymentException(this.message);
  @override
  String toString() => message;
}

class BoostPayment {
  /// Pull a payment reference out of a gateway URL, when it carries one.
  ///
  /// The Boost link usually carries `?t=<checkout token>`, which is NOT a reference
  /// VerifyPayment accepts — hence the reconciliation path in [confirmPayment].
  static String? extractReferenceId(String url) {
    if (url.isEmpty) return null;
    final m = RegExp(
      r'[?&](?:referenceId|reference_id|referenceid|reference|uuid|order_?id|bill_?id|transaction_?id)=([^&#]+)',
      caseSensitive: false,
    ).firstMatch(url);
    return m == null ? null : Uri.decodeComponent(m.group(1)!);
  }

  /// Ask the backend for a checkout URL.
  static Future<PaymentStart> start(PaymentIntent intent) async {
    final invoiceIds = intent.invoiceIds.where((i) => i > 0).toList();
    final term =
        (intent.term != null && !intent.term!.isEmpty) ? intent.term : null;
    final purchases = intent.purchaseItems;

    if (invoiceIds.isEmpty && term == null && purchases.isEmpty) {
      throw const BoostPaymentException('Nothing was selected to pay.');
    }
    // Probed live: a body carrying BOTH purchase lines and invoice ids still returns a
    // gateway URL, but the server takes the purchase path and the invoices are not
    // demonstrably billed. Never risk charging for a bill that silently dropped invoices.
    if (purchases.isNotEmpty && (invoiceIds.isNotEmpty || term != null)) {
      throw const BoostPaymentException(
        'Purchases have to be paid on their own — pay your invoices in a separate payment.',
      );
    }

    // Invoices are paid through the route the backend actually serves for them. `/Bcpg/PayInvoices`
    // rejects any body carrying invoice ids ("The JSON value could not be converted to
    // System.String. Path: $.status") and never returns a URL, so dues showed "Payment failed".
    // `/Outstanding/PayInvoices` with PaymentMethod=2 (FPX) answers with the checkout URL in
    // `data` — the flow the previous app used and the backend team verified. Advance months and
    // purchases keep the /Bcpg route: purchases work there, and it is the only route that bills
    // months with no invoice yet.
    final res = term == null && purchases.isEmpty
        ? await ApiService.postMultipart(
            '/Outstanding/PayInvoices',
            {'PaymentMethod': '2'},
            repeatedFields: {'InvoiceIds': invoiceIds.map((id) => '$id').toList()},
            onBoostHost: true,
          )
        : await ApiService.post('/Bcpg/PayInvoices', {
            'invoiceIds': invoiceIds,
            'payTermPayments': term?.toJson(),
            'purchaseItems': purchases.isEmpty
                ? null
                : purchases.map((p) => p.toJson()).toList(),
          });

    final url = urlFrom(res);
    if (url == null || url.isEmpty) {
      throw const BoostPaymentException(
          'No payment link was returned by the Boost gateway.');
    }
    return PaymentStart(url: url, referenceId: extractReferenceId(url));
  }

  /// The checkout URL in a `/Bcpg` reply, whichever key the server used.
  static String? urlFrom(dynamic res) {
    final data = unwrapData(res);
    if (data is String && data.trim().isNotEmpty) return data.trim();
    if (data is Map) {
      for (final k in ['url', 'paymentUrl', 'redirectUrl', 'link']) {
        final v = data[k];
        if (v is String && v.trim().isNotEmpty) return v.trim();
      }
    }
    return null;
  }

  static final _paid = RegExp(
      r'^(success|successful|paid|completed|complete|captured|settled|approved)$',
      caseSensitive: false);
  static final _failed = RegExp(
      r'^(failed|failure|cancelled|canceled|declined|rejected|expired)$',
      caseSensitive: false);

  /// What actually happened to a payment the user was sent to the gateway for.
  ///
  /// The browser never tells the app — `/Bcpg/Redirect` returns the BROWSER, not us — so
  /// this asks the server two independent ways and reports only what it can back up:
  ///
  ///  1. `GET /Bcpg/VerifyPayment/{ref}`, retried because the gateway callback can land
  ///     after the user comes back.
  ///  2. Reconciliation: refetch outstanding invoices per account and see whether the ones
  ///     being paid are gone. This is the signal that actually fires, because the Boost link
  ///     usually carries a checkout token rather than a reference.
  ///
  /// Returns [PaymentOutcome.unknown] rather than guessing. Never report success on a
  /// payment that cannot be corroborated.
  static Future<PaymentResult> confirm({
    String? referenceId,
    List<int> invoiceIds = const [],
    List<int?> studentIds = const [],
    int? purchaseBaseline,
    int attempts = 3,
    Duration delay = const Duration(seconds: 2),
    Future<List<int>> Function(int? studentId)? fetchOutstandingIds,
    Future<int> Function()? fetchPurchaseCount,
  }) async {
    String? gatewayStatus;

    if (referenceId != null && referenceId.isNotEmpty) {
      for (var i = 0; i < (attempts < 1 ? 1 : attempts); i++) {
        if (i > 0) await Future<void>.delayed(delay);
        try {
          final res = await ApiService.get(
              '/Bcpg/VerifyPayment/${Uri.encodeComponent(referenceId)}');
          final data = unwrapData(res);
          final status =
              (data is Map ? data['status'] : data)?.toString().trim() ?? '';
          if (status.isNotEmpty) gatewayStatus = status;
          if (_paid.hasMatch(status)) {
            return PaymentResult(PaymentOutcome.paid,
                'Payment confirmed by the gateway (ref $referenceId).',
                gatewayStatus: status);
          }
          if (_failed.hasMatch(status)) {
            return PaymentResult(PaymentOutcome.unpaid,
                'The gateway reported this payment as ${status.toLowerCase()}.',
                gatewayStatus: status);
          }
        } catch (_) {
          // An unknown reference 404s — fall through to reconciliation.
        }
      }
    }

    // Reconciliation. A parent can pay their own and their children's invoices in one
    // session while the outstanding list is scoped to a single student, so every account in
    // the payment is queried and the results unioned. Checking only the active account once
    // concluded the others were settled and told the user "Payment received" for a payment
    // that may never have gone through.
    if (invoiceIds.isNotEmpty && fetchOutstandingIds != null) {
      final accounts =
          studentIds.isEmpty ? <int?>[null] : studentIds.toSet().toList();
      final stillDue = <int>{};
      var queried = 0;
      for (final id in accounts) {
        try {
          stillDue.addAll(await fetchOutstandingIds(id));
          queried++;
        } catch (_) {
          // A failed lookup means we cannot prove anything — do not treat it as "settled".
        }
      }
      if (queried == accounts.length) {
        final unsettled = invoiceIds.where(stillDue.contains).toList();
        if (unsettled.isEmpty) {
          return PaymentResult(PaymentOutcome.paid,
              'Payment received — those invoices are no longer outstanding.',
              gatewayStatus: gatewayStatus);
        }
        final partial = unsettled.length < invoiceIds.toSet().length;
        return PaymentResult(
            partial ? PaymentOutcome.unknown : PaymentOutcome.unpaid,
            '${unsettled.length} of ${invoiceIds.toSet().length} invoice(s) are still outstanding.'
            '${partial ? ' Some invoices have settled. Check Payment History before paying again.' : ''}',
            gatewayStatus: gatewayStatus);
      }
    }

    if (purchaseBaseline != null && fetchPurchaseCount != null) {
      try {
        if (await fetchPurchaseCount() > purchaseBaseline) {
          return PaymentResult(PaymentOutcome.paid,
              'Payment received — your purchase request was created.',
              gatewayStatus: gatewayStatus);
        }
      } catch (_) {/* inconclusive */}
    }

    return PaymentResult(
        PaymentOutcome.unknown,
        'We could not confirm this payment yet. If money left your account it will appear '
        'shortly — check Payment History before paying again.',
        gatewayStatus: gatewayStatus);
  }
}
