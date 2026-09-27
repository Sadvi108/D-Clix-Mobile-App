// Boost gateway rules that must not regress.
//
// The money path is the one place where "probably fine" is not acceptable: a payment must
// never be reported as received unless it can be corroborated, and a purchase must never be
// mixed into an invoice payment (the server silently takes the purchase path and the
// invoices are not demonstrably billed).
import 'package:flutter_test/flutter_test.dart';
import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/boost_payment.dart';
import 'package:dclix_app/services/response_utils.dart';

void main() {
  group('host routing', () {
    test('/Bcpg goes to the Boost host, everything else stays on the API host',
        () {
      expect(
          ApiService.baseUrlFor('/Bcpg/PayInvoices'), ApiService.boostBaseUrl);
      expect(ApiService.baseUrlFor('/Bcpg/VerifyPayment/abc'),
          ApiService.boostBaseUrl);
      expect(
          ApiService.baseUrlFor('/Account/Authenticate'), ApiService.baseUrl);
      expect(ApiService.baseUrlFor('/Outstanding/Fetch'), ApiService.baseUrl);
      expect(ApiService.boostBaseUrl, isNot(ApiService.baseUrl),
          reason: 'the whole point is that Boost is served from elsewhere');
    });

    test('a path merely containing Bcpg is not treated as a Boost route', () {
      expect(ApiService.isBoostPath('/Reports/BcpgSummary'), isFalse);
      expect(ApiService.isBoostPath('/Bcpg/Callback'), isTrue);
    });

    test('/AutoPay goes to the Boost host too: production does not serve it', () {
      expect(ApiService.baseUrlFor('/AutoPay/Status'), ApiService.boostBaseUrl);
      expect(ApiService.baseUrlFor('/AutoPay/Enable'), ApiService.boostBaseUrl);
      expect(ApiService.isBoostPath('/Reports/AutoPaySummary'), isFalse);
    });
  });

  group('extractReferenceId', () {
    test('pulls a reference out of the query string', () {
      expect(
          BoostPayment.extractReferenceId('https://pay.x/?referenceId=ABC-123'),
          'ABC-123');
      expect(
          BoostPayment.extractReferenceId('https://pay.x/?a=1&reference_id=Z9'),
          'Z9');
      expect(BoostPayment.extractReferenceId('https://pay.x/?TransactionId=T7'),
          'T7');
    });

    test('url-decodes the value', () {
      expect(BoostPayment.extractReferenceId('https://pay.x/?reference=A%2FB'),
          'A/B');
    });

    test('a Boost checkout token is NOT a reference', () {
      // The live Boost link is `https://stage-pay.boostconnect.biz?t=<token>` — `t` is a
      // checkout token, not something VerifyPayment accepts. Treating it as a reference
      // would send the app polling an endpoint that can only ever 404.
      expect(
          BoostPayment.extractReferenceId(
              'https://stage-pay.boostconnect.biz?t=abc123'),
          isNull);
      expect(BoostPayment.extractReferenceId(''), isNull);
      expect(BoostPayment.extractReferenceId('https://pay.x/'), isNull);
    });
  });

  group('PaymentIntent validation', () {
    test('an empty intent is rejected before any network call', () async {
      await expectLater(
        BoostPayment.start(const PaymentIntent()),
        throwsA(isA<BoostPaymentException>()),
      );
    });

    test('purchases may not be mixed with invoices', () async {
      await expectLater(
        BoostPayment.start(const PaymentIntent(
          invoiceIds: [1542955],
          purchaseItems: [
            PurchaseItem(productId: 7, price: 50, totalAmount: 50)
          ],
        )),
        throwsA(predicate((e) =>
            e is BoostPaymentException && e.message.contains('on their own'))),
      );
    });

    test('purchases may not be mixed with advance months either', () async {
      await expectLater(
        BoostPayment.start(PaymentIntent(
          term: const TermPayment(studentIds: [1], year: 2026, months: [9]),
          purchaseItems: const [
            PurchaseItem(productId: 7, price: 50, totalAmount: 50)
          ],
        )),
        throwsA(isA<BoostPaymentException>()),
      );
    });

    test('an intent of only non-positive invoice ids counts as empty', () {
      expect(const PaymentIntent(invoiceIds: [0, -1]).isEmpty, isTrue);
      expect(const PaymentIntent(invoiceIds: [0, 5]).isEmpty, isFalse);
    });

    test('a term with no months counts as empty', () {
      expect(const TermPayment(studentIds: [1], year: 2026, months: []).isEmpty,
          isTrue);
      expect(const TermPayment(studentIds: [], year: 2026, months: [9]).isEmpty,
          isTrue);
    });
  });

  group('confirm — never claims success it cannot back up', () {
    test('invoices gone from every account -> paid', () async {
      final r = await BoostPayment.confirm(
        invoiceIds: [1, 2],
        studentIds: [10, 11],
        fetchOutstandingIds: (_) async => [99],
        attempts: 0,
      );
      expect(r.outcome, PaymentOutcome.paid);
    });

    test('partially settled invoices -> unknown', () async {
      final r = await BoostPayment.confirm(
        invoiceIds: [1, 2],
        studentIds: [10],
        fetchOutstandingIds: (_) async => [2],
        attempts: 0,
      );
      expect(r.outcome, PaymentOutcome.unknown);
      expect(r.message, contains('1 of 2'));
    });

    test('a sibling\'s invoice still due after partial settlement -> unknown',
        () async {
      // Reconciling against only the active account once concluded the other child's
      // invoices were settled and reported success for a payment that may not have gone
      // through. Every account in the payment must be queried and the results unioned.
      final r = await BoostPayment.confirm(
        invoiceIds: [1, 2],
        studentIds: [10, 11],
        fetchOutstandingIds: (id) async => id == 11 ? [2] : <int>[],
        attempts: 0,
      );
      expect(r.outcome, PaymentOutcome.unknown);
    });

    test('all selected invoices still outstanding -> unpaid', () async {
      final r = await BoostPayment.confirm(
          invoiceIds: [1, 2],
          studentIds: [10],
          fetchOutstandingIds: (_) async => [1, 2],
          attempts: 0);
      expect(r.outcome, PaymentOutcome.unpaid);
    });

    test('every lookup failing -> unknown, never paid', () async {
      final r = await BoostPayment.confirm(
        invoiceIds: [1],
        studentIds: [10],
        fetchOutstandingIds: (_) async => throw Exception('network down'),
        attempts: 0,
      );
      expect(r.outcome, PaymentOutcome.unknown,
          reason: 'an unreachable server is not evidence of payment');
    });

    test('nothing to reconcile -> unknown', () async {
      final r = await BoostPayment.confirm(attempts: 0);
      expect(r.outcome, PaymentOutcome.unknown);
    });

    test('a new purchase row -> paid', () async {
      final r = await BoostPayment.confirm(
        purchaseBaseline: 3,
        fetchPurchaseCount: () async => 4,
        attempts: 0,
      );
      expect(r.outcome, PaymentOutcome.paid);
    });

    test('purchase count unchanged -> unknown', () async {
      final r = await BoostPayment.confirm(
        purchaseBaseline: 3,
        fetchPurchaseCount: () async => 3,
        attempts: 0,
      );
      expect(r.outcome, PaymentOutcome.unknown);
    });
  });

  group('unwrapData', () {
    test('unwraps an envelope', () {
      expect(
          unwrapData({
            'status': 200,
            'meta': {'code': 200},
            'data': 'x'
          }),
          'x');
    });
    test('an envelope with no data unwraps to null, not the envelope', () {
      expect(
          unwrapData({
            'status': 200,
            'meta': {'code': 200}
          }),
          isNull);
    });
    test('a non-envelope payload is returned untouched', () {
      expect(unwrapData({'status': 'NotFound'}), {'status': 'NotFound'});
    });
  });
}
