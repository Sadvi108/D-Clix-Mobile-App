// Paying invoices goes through the route the backend actually serves.
//
// `/Bcpg/PayInvoices` answers 400 for anything carrying invoice ids ("The JSON value could not
// be converted to System.String. Path: $.status"), so dues never produced a gateway URL and the
// app showed "Payment failed". The backend team's working flow — and the one the previous app
// used — is `POST /Outstanding/PayInvoices` with PaymentMethod=2 (FPX), whose `data` is the
// checkout URL. Purchases keep the /Bcpg route, which does work for them.
import 'dart:convert';

import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/screens/payment/bcpg_webview_screen.dart';
import 'package:dclix_app/services/boost_payment.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _gatewayUrl = 'https://stage-pay.boostconnect.biz/?t=5gk6ucdKpHp2B92kZC0Khs';

http.Response _envelope(String url) => http.Response(
    jsonEncode({
      'status': 200,
      'meta': {'code': 200, 'error': null},
      'data': url
    }),
    200,
    headers: {'content-type': 'application/json'});

void main() {
  late List<http.Request> sent;

  setUp(() {
    sent = [];
    ApiService.client = MockClient((req) async {
      sent.add(req);
      return _envelope(_gatewayUrl);
    });
  });

  tearDown(() => ApiService.client = http.Client());

  Map<String, String> partsOf(http.Request req) {
    final fields = <String, String>{};
    for (final m in RegExp(r'name="([^"]+)"\r\n\r\n([^\r]*)').allMatches(req.body)) {
      final name = m.group(1)!;
      fields[name] = fields.containsKey(name) ? '${fields[name]},${m.group(2)}' : m.group(2)!;
    }
    return fields;
  }

  test('invoices are paid through /Outstanding/PayInvoices with PaymentMethod 2', () async {
    final start = await BoostPayment.start(const PaymentIntent(invoiceIds: [1000808, 1000809]));

    expect(start.url, _gatewayUrl);
    expect(sent, hasLength(1));
    expect(sent.single.url.path, '/Outstanding/PayInvoices');
    final fields = partsOf(sent.single);
    expect(fields['PaymentMethod'], '2');
    expect(fields['InvoiceIds'], '1000808,1000809');
  });

  test('the invoice payment carries no stale PayTermPayments/PurchaseItems query flags', () async {
    await BoostPayment.start(const PaymentIntent(invoiceIds: [1000808]));
    // Those query parameters are objects in the current API; the old `=false` values are
    // rejected outright, which is why they must not be sent for a plain invoice payment.
    expect(sent.single.url.query, isEmpty);
  });

  test('invoice payments go to the host that serves the Boost gateway', () async {
    await BoostPayment.start(const PaymentIntent(invoiceIds: [1000808]));
    expect(sent.single.url.origin, Uri.parse(ApiService.boostBaseUrl).origin);
  });

  test('purchases still use /Bcpg/PayInvoices', () async {
    await BoostPayment.start(const PaymentIntent(
        purchaseItems: [PurchaseItem(productId: 259, qty: 2, price: 20, totalAmount: 40)]));
    expect(sent.single.url.path, '/Bcpg/PayInvoices');
  });

  test('advance months still use /Bcpg/PayInvoices', () async {
    await BoostPayment.start(const PaymentIntent(
        term: TermPayment(studentIds: [35842], year: 2026, months: [10])));
    expect(sent.single.url.path, '/Bcpg/PayInvoices');
  });

  group('return leg', () {
    // The invoice gateway comes back through /Payment/Completed/{status} (and /Payment/Finalizing
    // on the way), not /Bcpg/Redirect. Unrecognised, the WebView would sit on the finished page
    // and the payment would never be verified.
    test('recognises the invoice gateway return pages', () {
      for (final url in [
        '${ApiService.baseUrl}/Payment/Completed/Success',
        '${ApiService.baseUrl}/Payment/Completed/Failed',
        '${ApiService.boostBaseUrl}/Payment/Completed/Success',
        '${ApiService.baseUrl}/Payment/Finalizing?referenceId=SUB68',
      ]) {
        expect(BcpgWebViewScreen.isMerchantReturn(url), isTrue, reason: url);
      }
    });

    test('still recognises the Bcpg return, and nothing off-host', () {
      expect(BcpgWebViewScreen.isMerchantReturn('${ApiService.boostBaseUrl}/Bcpg/Redirect?status=paid'), isTrue);
      expect(BcpgWebViewScreen.isMerchantReturn('https://unrelated.example/Payment/Completed/Success'), isFalse);
      expect(BcpgWebViewScreen.isMerchantReturn('https://stage-pay.boostconnect.biz/?t=abc'), isFalse);
    });
  });

  test('a reply with no URL is an error, never a silent success', () async {
    ApiService.client = MockClient((_) async => http.Response(
        jsonEncode({
          'status': 200,
          'meta': {'code': 200},
          'data': ''
        }),
        200,
        headers: {'content-type': 'application/json'}));
    await expectLater(
        BoostPayment.start(const PaymentIntent(invoiceIds: [1000808])), throwsA(isA<BoostPaymentException>()));
  });
}
