// The Boost host (/Bcpg/*) serves a self-signed Plesk certificate. Android's
// network_security_config trusts it, but Dart's HttpClient never reads that file, so every
// payment start died in the TLS handshake and the gateway never opened. The Dart client
// must accept exactly that certificate, and only on that host.
import 'dart:convert';
import 'dart:io';

import 'package:dclix_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final uatPem = File('android/app/src/main/res/raw/uat_apimacuat.pem').readAsStringSync();
  final otherPem = File('assets/certs/sectigo_public_server_authentication_root_r46.pem').readAsStringSync();

  test('accepts the pinned certificate on the Boost host', () {
    expect(ApiService.trustsBadCertificate('apimacuat.zyncbook.com', uatPem), isTrue);
  });

  test('matches the certificate Android pins, whatever the line endings', () {
    expect(ApiService.trustsBadCertificate('apimacuat.zyncbook.com', uatPem.replaceAll('\n', '\r\n')), isTrue);
  });

  test('rejects the same certificate on any other host', () {
    expect(ApiService.trustsBadCertificate('apimac.zyncbook.com', uatPem), isFalse);
    expect(ApiService.trustsBadCertificate('evil.example.com', uatPem), isFalse);
  });

  test('the WebView can check the same pin from the raw DER bytes it is handed', () {
    // flutter_inappwebview gives the certificate as DER, not PEM. Base64 of the DER is the PEM
    // body, so the one pin serves both the Dart client and the WebView.
    final der = base64Decode(uatPem.replaceAll(RegExp(r'-----[A-Z ]+-----|\s'), ''));
    expect(ApiService.trustsBadCertificate('apimacuat.zyncbook.com', base64Encode(der)), isTrue);
    expect(ApiService.trustsBadCertificate('stage-pay.boostconnect.biz', base64Encode(der)), isFalse);
  });

  test('rejects any other certificate on the Boost host', () {
    expect(ApiService.trustsBadCertificate('apimacuat.zyncbook.com', otherPem), isFalse);
  });
}
