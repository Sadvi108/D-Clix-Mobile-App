import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/autopay.dart';
import 'package:dclix_app/services/user_session.dart';

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

  group('the club\'s invoice types', () {
    final session = UserSession.instance;
    late Map<String, dynamic>? saved;
    setUp(() => saved = session.authData);
    tearDown(() => session.authData = saved);

    test('come from the sign-in payload, in the club\'s order', () {
      session.authData = {
        'autoPayAllowedInvoiceTypes': ['Monthly', 'Registration']
      };
      expect(AutoPay.clubInvoiceTypes(), ['Monthly', 'Registration']);
    });

    test('blank, repeated and non-text entries are dropped', () {
      session.authData = {
        'autoPayAllowedInvoiceTypes': [' Monthly ', '', '  ', null, 7, 'Registration', 'Monthly']
      };
      expect(AutoPay.clubInvoiceTypes(), ['Monthly', 'Registration']);
    });

    test('anything but a list, or no session, is "the club sent none"', () {
      for (final data in <Map<String, dynamic>?>[
        null,
        {},
        {'autoPayAllowedInvoiceTypes': null},
        {'autoPayAllowedInvoiceTypes': 'Monthly'},
      ]) {
        session.authData = data;
        expect(AutoPay.clubInvoiceTypes(), isEmpty, reason: '$data');
      }
    });
  });

  group('invoice type choices', () {
    tearDown(() => UserSession.instance.authData = null);

    test('the club\'s own list wins, and nothing is fetched', () async {
      var fetched = false;
      ApiService.client = MockClient((_) async {
        fetched = true;
        return _json(_ok([]));
      });
      UserSession.instance.authData = {
        'autoPayAllowedInvoiceTypes': ['Monthly', 'Registration']
      };
      expect(await AutoPay.invoiceTypeChoices(), ['Monthly', 'Registration']);
      expect(fetched, isFalse);
    });

    test('a club that sent none offers every type the academy lists', () async {
      ApiService.client = MockClient((req) async {
        expect(req.url.path, '/Listing/InvoceTypes');
        return _json(_ok([
          {'id': 1, 'text': 'Monthly'},
          {'id': 2, 'text': 'Grading'},
          {'id': 3, 'text': ' '},
        ]));
      });
      UserSession.instance.authData = {};
      expect(await AutoPay.invoiceTypeChoices(), ['Monthly', 'Grading']);
    });

    test('a failed listing offers no choice rather than failing the setup', () async {
      ApiService.client = MockClient((_) async => http.Response('', 500));
      UserSession.instance.authData = {};
      expect(await AutoPay.invoiceTypeChoices(), isEmpty);
    });
  });
}
