import 'api_service.dart';
import 'boost_payment.dart';
import 'response_utils.dart';

/// Auto Pay: a debit or credit card the member saves once on Boost's page. A server job
/// then pays that member's pending invoices with it.
///
/// Club.Api's contract (UAT swagger, 2026-09-27). The app sends only its bearer token; the
/// merchant secret stays on the server:
///
///   GET  /AutoPay/Status   -> data: {enabled, cardBrand, cardLast4, cardExpMonth, cardExpYear}
///   POST /AutoPay/Enable   -> data: the Boost card page URL. The member enters the card there;
///        Boost returns the browser to /AutoPay/Finalizing, which saves the token and redirects
///        to /Payment/Completed/{Success|Failed} — where the WebView hands control back.
///   POST /AutoPay/Disable  -> unlinks the card; turning it on again means entering a card again.
///
/// Charging the saved card each month is the server's job, never the app's. /AutoPay is served
/// by UAT only, so [ApiService.isBoostPath] sends it there. A 404 reads as "not open yet".
enum AutoPayState {
  off,

  /// Back from Boost, but the tokenization webhook has not confirmed the card yet.
  pending,
  active,

  /// The card was declined, or a scheduled payment failed. The member needs a new card.
  failed,
}

class AutoPayMandate {
  final AutoPayState state;

  /// "Visa", "Mastercard".
  final String? brand;
  final String? last4;

  /// "MM/YY".
  final String? expiry;
  final DateTime? nextCharge;

  /// The server's explanation when [state] is [AutoPayState.failed].
  final String? reason;

  const AutoPayMandate(
    this.state, {
    this.brand,
    this.last4,
    this.expiry,
    this.nextCharge,
    this.reason,
  });

  static const off = AutoPayMandate(AutoPayState.off);

  /// `AutoPayStatusViewModel`. Only `enabled: true` is on: telling a member their invoices
  /// are covered when they are not is the harm, so anything else reads as off.
  factory AutoPayMandate.fromJson(Map json) {
    String? s(String key) {
      final v = pickField(json, [key]);
      return v.isEmpty ? null : v;
    }

    final month = int.tryParse(s('cardExpMonth') ?? '');
    final year = int.tryParse(s('cardExpYear') ?? '');
    return AutoPayMandate(
      json['enabled'] == true ? AutoPayState.active : AutoPayState.off,
      brand: s('cardBrand'),
      last4: s('cardLast4'),
      expiry: month == null || year == null
          ? null
          : '${month.toString().padLeft(2, '0')}/${(year % 100).toString().padLeft(2, '0')}',
    );
  }

  /// "Visa •••• 4242", or "Your card" when the server sent no details.
  String get label {
    final name = brand ?? 'Your card';
    return last4 == null ? name : '$name •••• $last4';
  }
}

class AutoPay {
  static const _notYet = BoostPaymentException(
      'Auto Pay is not open yet. Please pay your fees from Fees Due for now.');

  static Future<AutoPayMandate> status() async {
    try {
      final data = unwrapData(await ApiService.get('/AutoPay/Status'));
      return data is Map ? AutoPayMandate.fromJson(data) : AutoPayMandate.off;
    } on ApiException catch (e) {
      // Not deployed yet: nobody can have a saved card, so "off" is the truth.
      if (e.statusCode == 404) return AutoPayMandate.off;
      rethrow;
    }
  }

  /// Ask the server for Boost's save-card page. Also used to replace the saved card.
  static Future<PaymentStart> setup() async {
    try {
      final res = await ApiService.post('/AutoPay/Enable', {});
      final url = BoostPayment.urlFrom(res);
      if (url == null) {
        throw const BoostPaymentException(
            'No card page was returned by the Boost gateway.');
      }
      return PaymentStart(url: url);
    } on ApiException catch (e) {
      if (e.statusCode == 404) throw _notYet;
      rethrow;
    }
  }

  static Future<void> cancel() async {
    try {
      await ApiService.post('/AutoPay/Disable', {});
    } on ApiException catch (e) {
      if (e.statusCode == 404) throw _notYet;
      rethrow;
    }
  }
}
