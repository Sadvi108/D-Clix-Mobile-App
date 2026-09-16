// Sign-in and Switch Branch failures must read as messages, not as exception dumps.
//
// Both stored `e.toString()` straight into UserSession.error, which the login screen and the
// Switch Branch alert print. Every other screen already went through friendlyError, so these
// two showed what the rest of the app hides: "SocketFailed host lookup: apimac.zyncbook.com",
// "ClientConnection closed…, uri=http://apimac.zyncbook.com/Account/Authenticate", and — when
// a Wi-Fi sign-in page answered in place of the API — that page's HTML.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:dclix_app/services/api_service.dart';
import 'package:dclix_app/services/user_session.dart';

const _network = 'Network error — please check your connection and try again.';
const _unexpected = 'Unexpected response from the server. Please try again.';

final _failures = <String, (MockClientHandler, String)>{
  'no connection': ((_) async => throw const SocketException('Failed host lookup: apimac.zyncbook.com'), _network),
  'dropped connection': (
    (r) async => throw http.ClientException('Connection closed before full header was received', r.url),
    _network
  ),
  'a Wi-Fi sign-in page instead of the API': (
    (_) async => http.Response('<html><title>Guest WiFi Login</title><body>Accept terms</body></html>', 200),
    _unexpected
  ),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  tearDown(() => ApiService.client = http.Client());

  final session = UserSession.instance;

  for (final MapEntry(key: name, value: (handler, message)) in _failures.entries) {
    test('sign-in: $name', () async {
      ApiService.client = MockClient(handler);
      final ok = await session.login(username: 'member', password: 'secret', userType: 3);
      expect(ok, isFalse);
      expect(session.error, message);
    });

    test('switch branch: $name', () async {
      session.authData = {'accessToken': 'token'};
      ApiService.client = MockClient(handler);
      final ok = await session.switchBranch(7);
      expect(ok, isFalse);
      expect(session.error, message);
    });
  }
}
