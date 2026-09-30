import 'api_service.dart';
import 'boost_payment.dart';
import 'response_utils.dart';
import 'rn_api.dart';
import 'user_session.dart';

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
/// Proposed, not on UAT yet (2026-09-30) — the screen is built against them:
///   POST /AutoPay/Enable   body {monthlyAmount, studentIds}: the amount to take each month, and
///        every family member (a family is all in or all out). Today's Enable takes no body, so
///        the server ignores both until it reads them.
///   POST /AutoPay/Pause, POST /AutoPay/Resume: hold payments without removing the card.
///   Status gains `paused` and `monthlyAmount`.
///
/// Charging the saved card each month is the server's job, never the app's. /AutoPay is served
/// by UAT only, so [ApiService.isBoostPath] sends it there. A 404 reads as "not open yet".
/// Everyone one Auto Pay covers: the signed-in account and its siblings.
typedef AutoPayFamily = List<({int id, String name})>;

enum AutoPayState {
  off,

  /// Back from Boost, but the tokenization webhook has not confirmed the card yet.
  pending,
  active,

  /// Card saved, but the member has put payments on hold until they resume.
  paused,

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

  /// What the member chose to have taken each month, when the server reports it.
  final double? monthlyAmount;

  const AutoPayMandate(
    this.state, {
    this.brand,
    this.last4,
    this.expiry,
    this.nextCharge,
    this.reason,
    this.monthlyAmount,
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
    final amount = json['monthlyAmount'];
    return AutoPayMandate(
      json['enabled'] != true
          ? AutoPayState.off
          : json['paused'] == true
              ? AutoPayState.paused
              : AutoPayState.active,
      brand: s('cardBrand'),
      last4: s('cardLast4'),
      expiry: month == null || year == null
          ? null
          : '${month.toString().padLeft(2, '0')}/${(year % 100).toString().padLeft(2, '0')}',
      monthlyAmount: amount is num ? amount.toDouble() : null,
    );
  }

  /// "Visa •••• 4242", or "Card •••• 5000" when the server sent no brand (Boost's sandbox
  /// sends none).
  String get label {
    final name = brand ?? 'Card';
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
  static Future<PaymentStart> setup(
      {double? monthlyAmount, List<int> studentIds = const []}) async {
    try {
      final res = await ApiService.post('/AutoPay/Enable', {
        if (monthlyAmount != null) 'monthlyAmount': monthlyAmount,
        if (studentIds.isNotEmpty) 'studentIds': studentIds,
      });
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

  static Future<void> pause() => _hold('/AutoPay/Pause', 'Pausing');

  static Future<void> resume() => _hold('/AutoPay/Resume', 'Resuming');

  static Future<void> _hold(String path, String what) async {
    try {
      await ApiService.post(path, {});
    } on ApiException catch (e) {
      // Not "not open yet": Auto Pay itself is on, only this action waits on the server.
      if (e.statusCode == 404) {
        throw BoostPaymentException(
            '$what Auto Pay is not available yet. Nothing was changed.');
      }
      rethrow;
    }
  }

  /// Everyone Auto Pay covers: the signed-in account and its siblings, as the Payments
  /// screen lists them. Siblings are optional — a failed lookup leaves just the account.
  static Future<AutoPayFamily> family() async {
    int id(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;
    final me = UserSession.instance.authData ?? const {};
    final out = [(id: id(me['id']), name: '${me['name'] ?? ''}'.trim())];
    try {
      for (final s in await RnApi.mySiblings()) {
        out.add((id: id(s['id']), name: '${s['text'] ?? ''}'.trim()));
      }
    } catch (_) {}
    final seen = <int>{};
    return out.where((m) => m.id > 0 && m.name.isNotEmpty && seen.add(m.id)).toList();
  }
}
