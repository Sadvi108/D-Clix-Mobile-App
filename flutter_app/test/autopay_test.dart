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

    test('paused reads as paused, and the monthly amount comes through', () async {
      ApiService.client = MockClient((_) async => _json(_ok({
            'enabled': true,
            'paused': true,
            'cardLast4': '5000',
            'monthlyAmount': 170,
          })));
      final m = await AutoPay.status();
      expect(m.state, AutoPayState.paused);
      expect(m.monthlyAmount, 170);
    });

    test('paused without enabled is still off', () async {
      ApiService.client = MockClient((_) async => _json(_ok({'enabled': false, 'paused': true})));
      expect((await AutoPay.status()).state, AutoPayState.off);
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

    test('Enable carries the monthly amount and every family member', () async {
      Object? body;
      ApiService.client = MockClient((req) async {
        body = jsonDecode(req.body);
        return _json(_ok('https://stage-pay.boostconnect.biz?t=abc'));
      });
      await AutoPay.setup(monthlyAmount: 170, studentIds: [11, 12]);
      expect(body, {'monthlyAmount': 170, 'studentIds': [11, 12]});
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
}
