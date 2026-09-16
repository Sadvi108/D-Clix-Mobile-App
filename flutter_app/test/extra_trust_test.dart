// The bundled Sectigo R46 root lets older Android phones load member photos and club logos
// from https://www.maclubsystem.com. See lib/services/extra_trust.dart.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:dclix_app/services/extra_trust.dart';

void main() {
  final pem = File(ExtraTrust.sectigoR46Asset);

  test('the R46 root certificate is bundled as a registered asset', () {
    expect(pem.existsSync(), isTrue);
    expect(File('pubspec.yaml').readAsStringSync(), contains('- assets/certs/'));
  });

  test('the bundled file is exactly the Sectigo R46 root', () {
    final text = pem.readAsStringSync();
    expect('BEGIN CERTIFICATE'.allMatches(text), hasLength(1));
    // First and last base64 lines of the certificate published by Sectigo (SHA-256
    // 7B:B6:47:A6:2A:EE:AC:88:BF:25:7A:A5:22:D0:1F:FE:A3:95:E0:AB:45:C7:3F:93:F6:56:54:EC:38:F2:5A:06).
    expect(text, contains('MIIFijCCA3KgAwIBAgIQdY39i658BwD6qSWn4cetFDANBgkqhkiG9w0BAQwFADBf'));
    expect(text, contains('QqszKbrAKbkTidOIijlBO8n9pu0f9GBj39ItVQGL'));
  });

  test('it parses as a trust anchor, comment header included', () {
    expect(() => SecurityContext(withTrustedRoots: false).setTrustedCertificatesBytes(pem.readAsBytesSync()),
        returnsNormally);
  });

  test('install is a no-op off Android', () async {
    await ExtraTrust.install(isAndroid: false);
  });
}
