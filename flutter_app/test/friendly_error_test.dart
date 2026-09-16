import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:dclix_app/services/response_utils.dart';

void main() {
  group('friendlyError', () {
    test('network / CORS / socket errors become a connection message', () {
      expect(friendlyError('ClientException: XMLHttpRequest error., uri=...'),
          'Network error — please check your connection and try again.');
      expect(friendlyError(Exception('SocketException: Failed host lookup')),
          'Network error — please check your connection and try again.');
    });

    test('401 becomes a session-expired message', () {
      expect(friendlyError('Exception: ❌ Unauthorized - Token missing or expired'),
          'Your session has expired. Please log in again.');
    });

    test('server 5xx becomes a try-later message', () {
      expect(friendlyError('Exception: ❌ Error 500: boom'),
          'Server error — please try again in a moment.');
    });

    test('a body that is not JSON never reaches the screen', () {
      // Over plain HTTP a Wi-Fi sign-in page or proxy error page answers in place of the
      // API. jsonDecode's FormatException quotes that page back, HTML and all.
      const page = '<html><head><title>Guest WiFi Login</title></head><body>Accept terms</body></html>';
      Object? error;
      try {
        jsonDecode(page);
      } catch (e) {
        error = e;
      }
      expect(error, isA<FormatException>());
      for (final e in [error, error.toString()]) {
        expect(friendlyError(e), 'Unexpected response from the server. Please try again.');
      }
    });

    test('strips the Exception/glyph prefix from other messages', () {
      expect(friendlyError('Exception: ❌ Something specific'),
          'Something specific');
    });

    test('blank / unknown falls back to a generic message', () {
      expect(friendlyError(''), 'Something went wrong. Please try again.');
    });
  });
}
