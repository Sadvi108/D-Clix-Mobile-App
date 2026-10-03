import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/autopay.dart';

http.Response _json(Object body, [int status = 200]) => http.Response(
    jsonEncode(body), status,
    headers: {'content-type': 'application/json; charset=utf-8'});

/// The envelope Club.Api wraps every reply in.
Map<String, Object?> _ok(Object? data) => {
      'status': 200,
      'meta': {'code': 200, 'error': null},
      'data': data
    };

void main() {
  late http.Client original;
  setUp(() => original = ApiService.client);
  tearDown(() => ApiService.client = original);

  group('status', () {
    test('GET /AutoPay/Status on the Boost host reads the saved card', () async {
      ApiService.client = MockClient((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/AutoPay/Status');
        expect(req.url.origin, Uri.parse(ApiService.boostBaseUrl).origin,
            reason: '/AutoPay exists only on UAT, like /Bcpg');
        // AutoPayStatusViewModel, verified against the UAT swagger.
        return _json(_ok({
          'enabled': true,
          'cardBrand': 'Visa',
          'cardLast4': '4242',
          'cardExpMonth': 8,
          'cardExpYear': 2028,
        }));
      });
      final m = await AutoPay.status();
      expect(m.state, AutoPayState.active);
      expect(m.label, 'Visa •••• 4242');
      expect(m.expiry, '08/28');
    });

    test('enabled false is off, even with a stale card on file', () async {
      ApiService.client = MockClient((_) async => _json(_ok({
            'enabled': false,
            'cardBrand': 'Visa',
            'cardLast4': '4242',
          })));
      expect((await AutoPay.status()).state, AutoPayState.off);
    });

    test('status "Paused" reads as paused, and the plan comes through', () async {
      ApiService.client = MockClient((_) async => _json(_ok({
            'enabled': true,
            'status': 'Paused',
            'cardLast4': '5000',
            'selectedInvoiceTypes': ['Monthly', 'Registration'],
            'perChargeCap': 170,
          })));
      final m = await AutoPay.status();
      expect(m.state, AutoPayState.paused);
      expect(m.invoiceTypes, ['Monthly', 'Registration']);
      expect(m.perChargeCap, 170);
    });

    test('"paused" in any case is paused; any other status is active', () async {
      for (final (status, state) in [
        ('paused', AutoPayState.paused),
        ('PAUSED', AutoPayState.paused),
        ('Active', AutoPayState.active),
        (null, AutoPayState.active),
      ]) {
        ApiService.client =
            MockClient((_) async => _json(_ok({'enabled': true, 'status': status})));
        expect((await AutoPay.status()).state, state, reason: 'status $status');
      }
    });

    test('the old `paused: true` still reads as paused', () async {
      ApiService.client =
          MockClient((_) async => _json(_ok({'enabled': true, 'paused': true})));
      expect((await AutoPay.status()).state, AutoPayState.paused);
    });

    test('paused without enabled is still off', () async {
      ApiService.client = MockClient((_) async =>
          _json(_ok({'enabled': false, 'status': 'Paused', 'paused': true})));
      expect((await AutoPay.status()).state, AutoPayState.off);
    });

    test('no plan from the server reads as none, not as zero', () async {
      ApiService.client = MockClient((_) async => _json(_ok({
            'enabled': true,
            'selectedInvoiceTypes': null,
            'perChargeCap': null,
          })));
      final m = await AutoPay.status();
      expect(m.invoiceTypes, isEmpty);
      expect(m.perChargeCap, isNull);
    });

    test('a reply without `enabled` is off, never active', () async {
      ApiService.client = MockClient((_) async => _json(_ok({'cardLast4': '4242'})));
      expect((await AutoPay.status()).state, AutoPayState.off);
    });

    test('route not deployed reads as off, not as an error', () async {
      ApiService.client = MockClient((_) async => http.Response('', 404));
      expect((await AutoPay.status()).state, AutoPayState.off);
    });

    test('other failures surface', () async {
      ApiService.client = MockClient((_) async => http.Response('', 500));
      expect(AutoPay.status(), throwsA(isA<ApiException>()));
    });
  });

  test('a card without a brand reads as Card, not "Your card"', () {
    // Boost's sandbox sends no brand; the label is also used mid-sentence.
    expect(const AutoPayMandate(AutoPayState.active, last4: '5000').label, 'Card •••• 5000');
  });

  group('setup', () {
    test('POST /AutoPay/Enable returns the Boost card page from `data`', () async {
      ApiService.client = MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/AutoPay/Enable');
        expect(req.url.origin, Uri.parse(ApiService.boostBaseUrl).origin);
        return _json(_ok('https://stage-pay.boostconnect.biz?t=abc'));
      });
      final start = await AutoPay.setup();
      expect(start.url, 'https://stage-pay.boostconnect.biz?t=abc');
    });

    test('Enable sends exactly the invoice types, the per-payment cap and the consent',
        () async {
      Object? body;
      ApiService.client = MockClient((req) async {
        body = jsonDecode(req.body);
        return _json(_ok('https://stage-pay.boostconnect.biz?t=abc'));
      });
      await AutoPay.setup(
          invoiceTypes: ['Monthly', 'Registration'],
          perChargeCap: 170,
          consentVersion: 'terms-v1');
      // AutoPayEnableRequestViewModel takes no other field (additionalProperties: false).
      expect(body, {
        'invoiceTypes': ['Monthly', 'Registration'],
        'perChargeCap': 170,
        'consentVersion': 'terms-v1',
      });
    });

    test('Enable leaves out what it was not given, rather than sending null', () async {
      Object? body;
      ApiService.client = MockClient((req) async {
        body = jsonDecode(req.body);
        return _json(_ok('https://stage-pay.boostconnect.biz?t=abc'));
      });
      await AutoPay.setup(perChargeCap: 50, consentVersion: 'terms-v1');
      expect(body, {'perChargeCap': 50, 'consentVersion': 'terms-v1'});
    });

    test('no URL back is an error, never a blank page', () async {
      ApiService.client = MockClient((_) async => _json(_ok('')));
      expect(AutoPay.setup(), throwsA(anything));
    });

    test('route not deployed says so', () async {
      ApiService.client = MockClient((_) async => http.Response('', 404));
      expect(
          AutoPay.setup(),
          throwsA(predicate((e) => e.toString().contains('not open yet'))));
    });
  });

  test('cancel posts to /AutoPay/Disable on the Boost host', () async {
    Uri? url;
    String? method;
    ApiService.client = MockClient((req) async {
      url = req.url;
      method = req.method;
      return _json(_ok(null));
    });
    await AutoPay.cancel();
    expect(method, 'POST');
    expect(url!.path, '/AutoPay/Disable');
    expect(url!.origin, Uri.parse(ApiService.boostBaseUrl).origin);
  });

  group('pause and resume', () {
    for (final (name, call, path) in [
      ('pause', AutoPay.pause, '/AutoPay/Pause'),
      ('resume', AutoPay.resume, '/AutoPay/Resume'),
    ]) {
      test('$name posts to $path on the Boost host', () async {
        Uri? url;
        ApiService.client = MockClient((req) async {
          url = req.url;
          return _json(_ok(null));
        });
        await call();
        expect(url!.path, path);
        expect(url!.origin, Uri.parse(ApiService.boostBaseUrl).origin);
      });

      test('$name not deployed says so, and does not claim Auto Pay is off', () async {
        ApiService.client = MockClient((_) async => http.Response('', 404));
        expect(
            call(),
            throwsA(predicate((e) =>
                e.toString().contains('not available yet') &&
                !e.toString().contains('not open yet'))));
      });
    }
  });

  group('invoice type choices', () {
    test('the club\'s portal list from /AutoPay/AllowedInvoiceTypes wins', () async {
      final asked = <String>[];
      ApiService.client = MockClient((req) async {
        asked.add(req.url.path);
        expect(req.url.origin, Uri.parse(ApiService.boostBaseUrl).origin);
        return _json(_ok(['Monthly', 'Registration']));
      });
      expect(await AutoPay.invoiceTypeChoices(), ['Monthly', 'Registration']);
      expect(asked, ['/AutoPay/AllowedInvoiceTypes'], reason: 'no academy listing needed');
    });

    test('a club with no list set offers every type the academy lists', () async {
      ApiService.client = MockClient((req) async => switch (req.url.path) {
            '/AutoPay/AllowedInvoiceTypes' => _json(_ok([])),
            '/Listing/InvoceTypes' => _json(_ok([
                {'id': 'Monthly', 'text': 'Monthly'},
                {'id': 'Grading', 'text': 'Grading'},
                {'id': '', 'text': ' '},
              ])),
            _ => http.Response('', 404),
          });
      expect(await AutoPay.invoiceTypeChoices(), ['Monthly', 'Grading']);
    });

    test('when the club list cannot be read, no choice is offered rather than a guess',
        () async {
      // Offering every academy type here is what made Enable refuse with "not allowed for
      // auto pay by this club": the club list is the authority, so without it, ask nothing.
      ApiService.client = MockClient((req) async => req.url.path == '/Listing/InvoceTypes'
          ? _json(_ok([{'id': 'Grading', 'text': 'Grading'}]))
          : http.Response('', 500));
      expect(await AutoPay.invoiceTypeChoices(), isEmpty);
    });
  });

  group('consent content', () {
    test('GET /AutoPay/ConsentContent gives the version, the boxes and the terms link',
        () async {
      ApiService.client = MockClient((req) async {
        expect(req.url.path, '/AutoPay/ConsentContent');
        expect(req.url.origin, Uri.parse(ApiService.boostBaseUrl).origin);
        return _json(_ok({
          'version': 'v3',
          'checkboxes': [
            {'key': 'cardholder', 'text': 'I am the cardholder.'},
            {'key': 'terms', 'text': 'I agree to the terms.'},
            {'key': '', 'text': ''},
          ],
          'termsUrl': 'https://example.com/terms',
        }));
      });
      final c = await AutoPay.consent();
      expect(c.version, 'v3');
      expect(c.checkboxes.map((b) => b.key), ['cardholder', 'terms'],
          reason: 'a box with no text cannot be agreed to');
      expect(c.termsUrl, 'https://example.com/terms');
    });

    test('a reply that is not the agreement is an error, never an empty agreement',
        () async {
      ApiService.client = MockClient((_) async => _json(_ok(null)));
      expect(AutoPay.consent(), throwsA(anything));
    });
  });

  test('UpdateSettings changes the plan in place', () async {
    late http.Request sent;
    ApiService.client = MockClient((req) async {
      sent = req;
      return _json(_ok('Updated'));
    });
    await AutoPay.updateSettings(invoiceTypes: ['Monthly'], perChargeCap: 90);
    expect(sent.method, 'POST');
    expect(sent.url.path, '/AutoPay/UpdateSettings');
    expect(sent.url.origin, Uri.parse(ApiService.boostBaseUrl).origin);
    expect(jsonDecode(sent.body), {'invoiceTypes': ['Monthly'], 'perChargeCap': 90});
  });
}
