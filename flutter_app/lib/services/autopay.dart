import 'api_service.dart';
import 'boost_payment.dart';
import 'response_utils.dart';
import 'rn_api.dart';
import 'user_session.dart';

/// Auto Pay: a debit or credit card the member saves once on Boost's page. A server job
/// then pays that member's pending invoices with it.
///
/// Club.Api's contract (UAT swagger, 2026-10-03). The app sends only its bearer token; the
/// merchant secret stays on the server:
///
///   GET  /AutoPay/Status   -> data: {enabled, status, cardBrand, cardLast4, cardExpMonth,
///        cardExpYear, selectedInvoiceTypes, perChargeCap}. Status "Paused" is on hold.
///   POST /AutoPay/Enable   body {invoiceTypes, perChargeCap, consentVersion}: which of the
///        club's invoice types to pay, the most one payment may take, and the recurring billing
///        terms the member agreed to. -> data: the Boost card page URL. The member enters the
///        card there; Boost returns the browser to /AutoPay/Finalizing, which saves the token
///        and redirects to /Payment/Completed/{Success|Failed} — where the WebView hands
///        control back. Every family member is covered; there is no per-member field.
///   POST /AutoPay/Pause, POST /AutoPay/Resume (no body): hold payments, keeping the card.
///   POST /AutoPay/Disable  -> unlinks the card; turning it on again means entering a card again.
///   GET  /AutoPay/AllowedInvoiceTypes -> data: string[], the types the club allows in its
///        portal. Enable refuses any other type.
///   GET  /AutoPay/ConsentContent -> data: {version, checkboxes: [{key, text}], termsUrl}, the
///        agreement the member ticks before Boost; Enable sends back its version.
///   POST /AutoPay/UpdateSettings body {invoiceTypes, perChargeCap}: change the plan while on,
///        keeping the card.
///
/// Charging the saved card is the server's job, never the app's. /AutoPay is served by UAT
/// only, so [ApiService.isBoostPath] sends it there. A 404 reads as "not open yet".
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

  /// The invoice types Auto Pay pays ("Monthly", "Registration"); empty when the server
  /// reported none.
  final List<String> invoiceTypes;

  /// The most Auto Pay takes in one payment, when the server reports it.
  final double? perChargeCap;

  const AutoPayMandate(
    this.state, {
    this.brand,
    this.last4,
    this.expiry,
    this.nextCharge,
    this.reason,
    this.invoiceTypes = const [],
    this.perChargeCap,
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
    final cap = json['perChargeCap'];
    return AutoPayMandate(
      json['enabled'] != true
          ? AutoPayState.off
          // `status` replaced an earlier `paused` flag; either one means on hold.
          : s('status')?.toLowerCase() == 'paused' || json['paused'] == true
              ? AutoPayState.paused
              : AutoPayState.active,
      brand: s('cardBrand'),
      last4: s('cardLast4'),
      expiry: month == null || year == null
          ? null
          : '${month.toString().padLeft(2, '0')}/${(year % 100).toString().padLeft(2, '0')}',
      invoiceTypes: _names(json['selectedInvoiceTypes']),
      perChargeCap: cap is num ? cap.toDouble() : null,
    );
  }

  /// "Visa •••• 4242", or "Card •••• 5000" when the server sent no brand (Boost's sandbox
  /// sends none).
  String get label {
    final name = brand ?? 'Card';
    return last4 == null ? name : '$name •••• $last4';
  }
}

/// The agreement the member ticks before Boost, as the club's server words it.
class AutoPayConsent {
  /// Sent back with Enable, so the server records which wording was agreed to.
  final String? version;

  /// Every box must be ticked. Boxes without text are dropped: nothing to agree to.
  final List<({String key, String text})> checkboxes;
  final String? termsUrl;

  const AutoPayConsent({this.version, this.checkboxes = const [], this.termsUrl});

  factory AutoPayConsent.fromJson(Map json) {
    String? s(Object? v) => v is String && v.trim().isNotEmpty ? v.trim() : null;
    final boxes = json['checkboxes'];
    return AutoPayConsent(
      version: s(json['version']),
      checkboxes: [
        if (boxes is List)
          for (final b in boxes)
            if (b is Map && s(b['text']) != null)
              (key: s(b['key']) ?? s(b['text'])!, text: s(b['text'])!),
      ],
      termsUrl: s(json['termsUrl']),
    );
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
  /// A null leaves its field out, and the server applies its own default.
  static Future<PaymentStart> setup(
      {List<String>? invoiceTypes, double? perChargeCap, String? consentVersion}) async {
    try {
      final res = await ApiService.post('/AutoPay/Enable', {
        if (invoiceTypes != null) 'invoiceTypes': invoiceTypes,
        if (perChargeCap != null) 'perChargeCap': perChargeCap,
        if (consentVersion != null) 'consentVersion': consentVersion,
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

  // Literal paths, so api_wiring_test can see and check both routes.
  static Future<void> pause() =>
      _hold(() => ApiService.post('/AutoPay/Pause', {}), 'Pausing');

  static Future<void> resume() =>
      _hold(() => ApiService.post('/AutoPay/Resume', {}), 'Resuming');

  static Future<void> _hold(Future<dynamic> Function() post, String what) async {
    try {
      await post();
    } on ApiException catch (e) {
      // Not "not open yet": Auto Pay itself is on, only this action waits on the server.
      if (e.statusCode == 404) {
        throw BoostPaymentException(
            '$what Auto Pay is not available yet. Nothing was changed.');
      }
      rethrow;
    }
  }

  /// Change the invoice types or the limit per transaction while Auto Pay is on. The card stays.
  static Future<void> updateSettings({List<String>? invoiceTypes, double? perChargeCap}) =>
      ApiService.post('/AutoPay/UpdateSettings', {
        if (invoiceTypes != null) 'invoiceTypes': invoiceTypes,
        if (perChargeCap != null) 'perChargeCap': perChargeCap,
      });

  /// The agreement to show before Boost. A reply that is not the agreement is an error: an
  /// empty agreement must never be "agreed" to.
  static Future<AutoPayConsent> consent() async {
    final data = unwrapData(await ApiService.get('/AutoPay/ConsentContent'));
    if (data is! Map) {
      throw const BoostPaymentException(
          'The Auto Pay agreement could not be loaded. Please try again.');
    }
    return AutoPayConsent.fromJson(data);
  }

  /// The invoice types the club allows in its portal. Empty when it set none.
  static Future<List<String>> allowedInvoiceTypes() async =>
      _names(unwrapData(await ApiService.get('/AutoPay/AllowedInvoiceTypes')));

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

  /// The types a member may tick in the setup sheet: the club's portal list. A club that set
  /// none placed no limit, so every type the academy lists (/Listing/InvoceTypes, the list Pay
  /// Your Dues filters by). When the club list cannot be read, no choice is offered and Enable
  /// leaves the types to the server: guessing every academy type is what Enable refuses.
  static Future<List<String>> invoiceTypeChoices() async {
    final List<String> club;
    try {
      club = await allowedInvoiceTypes();
    } catch (_) {
      return const [];
    }
    if (club.isNotEmpty) return club;
    try {
      final rows = await RnApi.invoiceTypes();
      return _names([for (final r in rows) pickField(r, ['text', 'name'])]);
    } catch (_) {
      return const [];
    }
  }
}

/// A server list of names, trimmed, without blanks, repeats or anything not text. Anything
/// but a list is no names.
List<String> _names(Object? v) => v is List
    ? [...{for (final e in v) if (e is String && e.trim().isNotEmpty) e.trim()}]
    : const [];
