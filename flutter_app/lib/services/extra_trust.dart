import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Public root certificates that older Android trust stores lack.
///
/// Member photos and club logos are served from `https://www.maclubsystem.com`, whose
/// certificate chains to "Sectigo Public Server Authentication Root R46" (2021). The server
/// sends the leaf and the "DV R36" intermediate but not the cross-signed R46, so a device
/// without R46 in its store cannot build a chain. iOS and Android 13+ ship R46; Android 7–12
/// phones do not, and Dart's HTTP stack reads the device store, so every photo failed there
/// and fell back to initials.
///
/// Adding the root to Dart's default context fixes it for every `HttpClient` / `package:http`
/// client, including the image cache. It only adds trust for certificates issued under that
/// Sectigo root; nothing else changes. The proper server fix is to serve the full chain.
class ExtraTrust {
  ExtraTrust._();

  static const sectigoR46Asset = 'assets/certs/sectigo_public_server_authentication_root_r46.pem';

  /// Call once before any network request. No-op off Android.
  static Future<void> install({AssetBundle? bundle, bool? isAndroid}) async {
    if (kIsWeb || !(isAndroid ?? Platform.isAndroid)) return;
    try {
      final data = await (bundle ?? rootBundle).load(sectigoR46Asset);
      SecurityContext.defaultContext.setTrustedCertificatesBytes(data.buffer.asUint8List());
    } catch (e) {
      // A device that already trusts R46 still loads photos; never block start-up on this.
      debugPrint('Extra trust anchor not installed: $e');
    }
  }
}
